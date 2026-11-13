import Metal
import QuartzCore
import simd

enum ArenaRendererError: Error {
    case noMetal
    case noShaders
    case outOfMemory
}

/// Draws the arena with Metal: a shadow pass for the bones, then the haze, the felt carpet with
/// its stitched markings, the bones and the aim dots, 4× MSAA, up to 120 fps (ADR-001).
@MainActor
final class ArenaRenderer {
    /// Mirrors `BoneInstance` in ArenaShaders.metal.
    struct BoneInstance {
        var model: simd_float4x4
        /// rgb albedo (linear), a: gloss.
        var color: SIMD4<Float>
        /// x: painted, y: glow.
        var params: SIMD4<Float> = .zero
    }

    /// Mirrors `DotInstance` in ArenaShaders.metal.
    struct DotInstance {
        /// xyz, w: radius in pixels.
        var position: SIMD4<Float>
        /// Premultiplied.
        var color: SIMD4<Float>
    }

    /// The carpet and everything drawn on it.
    struct Field {
        var circleRadius: Float = 2.5
        var konHalfLength: Float = 0.575
        var nearThrowZ: Float = 6
        var farThrowZ: Float = -6
        /// From (x, z) to (x, z); `aimVisibility` 0 hides the guide.
        var aimFrom = SIMD2<Float>(0, 6)
        var aimTo = SIMD2<Float>(0, 0)
        var aimVisibility: Float = 0
        var landingRingRadius: Float = 0.1
        /// xy: center (x, z), z: age 0…1, w: strength. At most 4.
        var ripples: [SIMD4<Float>] = []
        /// xyz: bone center, w: footprint radius. At most 24.
        var contacts: [SIMD4<Float>] = []

        /// Laid out as `FieldUniforms` in ArenaShaders.metal: 35 float4s.
        func packed() -> [SIMD4<Float>] {
            var values: [SIMD4<Float>] = []
            values.reserveCapacity(35)
            values.append(SIMD4(Palette.felt.linear, 1))
            values.append(SIMD4(Palette.thread.linear, 0.92))
            values.append(SIMD4(circleRadius, FieldGeometry.circleLineWidth, konHalfLength, FieldGeometry.parallelLineOffset))
            values.append(SIMD4(nearThrowZ, farThrowZ, FieldGeometry.throwLineHalfWidth, 0.04))
            values.append(SIMD4(aimFrom.x, aimFrom.y, aimTo.x, aimTo.y))
            values.append(SIMD4(aimVisibility, landingRingRadius, 0, 0))
            for index in 0..<4 {
                values.append(index < ripples.count ? ripples[index] : SIMD4(0, 0, -1, 0))
            }
            for index in 0..<24 {
                values.append(index < contacts.count ? contacts[index] : .zero)
            }
            values.append(SIMD4(Float(min(contacts.count, 24)), 0, 0, 0))
            return values
        }
    }

    /// Everything one frame shows.
    struct Scene {
        var camera: ArenaCamera
        var time: Float
        var field: Field
        var kenei: [BoneInstance]
        /// Saqas on the field: they cast shadows.
        var saqa: [BoneInstance]
        /// The saqa in the hand, near the camera: lit, but casts no shadow.
        var hand: [BoneInstance]
        var dots: [DotInstance]
        /// The shadow map follows the action.
        var shadowFocus: SIMD3<Float>
    }

    // Mirrors `FrameUniforms` in ArenaShaders.metal.
    private struct FrameUniforms {
        var viewProjection: simd_float4x4
        var inverseViewProjection: simd_float4x4
        var lightViewProjection: simd_float4x4
        var cameraPosition: SIMD4<Float>
        var lightDirection: SIMD4<Float>
        var lightColor: SIMD4<Float>
        var sky: SIMD4<Float>
        var bounce: SIMD4<Float>
        var haze: SIMD4<Float>
        var zenith: SIMD4<Float>
        var stage: SIMD4<Float>
        var shadow: SIMD4<Float>
    }

    private struct Mesh {
        let vertices: MTLBuffer
        let indices: MTLBuffer
        let indexCount: Int
        /// xyz half extents, w: corner radius; the shader finds the shik hollow with it.
        let extents: SIMD4<Float>
    }

    static let pixelFormat = MTLPixelFormat.bgra8Unorm_srgb
    private static let depthFormat = MTLPixelFormat.depth32Float
    private static let sampleCount = 4
    private static let maxBones = 64
    private static let maxDots = 64
    private static let framesInFlight = 3

    let device: MTLDevice
    private let queue: MTLCommandQueue
    private let backgroundPipeline: MTLRenderPipelineState
    private let groundPipeline: MTLRenderPipelineState
    private let bonePipeline: MTLRenderPipelineState
    private let shadowPipeline: MTLRenderPipelineState
    private let dotPipeline: MTLRenderPipelineState
    private let depthState: MTLDepthStencilState
    private let noDepthState: MTLDepthStencilState
    private let overlayDepthState: MTLDepthStencilState
    private let keneiMesh: Mesh
    private let saqaMesh: Mesh
    private let shadowMap: MTLTexture
    private var boneBuffers: [MTLBuffer] = []
    private var dotBuffers: [MTLBuffer] = []
    private var bufferIndex = 0
    private let inFlight = DispatchSemaphore(value: ArenaRenderer.framesInFlight)
    private var targets: (color: MTLTexture, depth: MTLTexture)?

    init() throws {
        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue() else {
            throw ArenaRendererError.noMetal
        }
        guard let library = device.makeDefaultLibrary() else { throw ArenaRendererError.noShaders }
        func function(_ name: String) throws -> MTLFunction {
            guard let function = library.makeFunction(name: name) else { throw ArenaRendererError.noShaders }
            return function
        }

        func pipeline(_ vertex: String, _ fragment: String, blended: Bool = false) throws -> MTLRenderPipelineState {
            let descriptor = MTLRenderPipelineDescriptor()
            descriptor.vertexFunction = try function(vertex)
            descriptor.fragmentFunction = try function(fragment)
            descriptor.colorAttachments[0].pixelFormat = Self.pixelFormat
            descriptor.depthAttachmentPixelFormat = Self.depthFormat
            descriptor.rasterSampleCount = Self.sampleCount
            if blended {
                // Fragments return premultiplied alpha.
                let attachment = descriptor.colorAttachments[0]!
                attachment.isBlendingEnabled = true
                attachment.sourceRGBBlendFactor = .one
                attachment.sourceAlphaBlendFactor = .one
                attachment.destinationRGBBlendFactor = .oneMinusSourceAlpha
                attachment.destinationAlphaBlendFactor = .oneMinusSourceAlpha
            }
            return try device.makeRenderPipelineState(descriptor: descriptor)
        }

        let shadowDescriptor = MTLRenderPipelineDescriptor()
        shadowDescriptor.vertexFunction = try function("boneShadowVertex")
        shadowDescriptor.depthAttachmentPixelFormat = Self.depthFormat

        func depthState(compare: MTLCompareFunction, write: Bool) throws -> MTLDepthStencilState {
            let descriptor = MTLDepthStencilDescriptor()
            descriptor.depthCompareFunction = compare
            descriptor.isDepthWriteEnabled = write
            guard let state = device.makeDepthStencilState(descriptor: descriptor) else { throw ArenaRendererError.noMetal }
            return state
        }

        let shadowSize = GameTuning.Light.shadowMapSize
        let shadowTexture = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: Self.depthFormat, width: shadowSize, height: shadowSize, mipmapped: false)
        shadowTexture.usage = [.renderTarget, .shaderRead]
        shadowTexture.storageMode = .private
        guard let shadowMap = device.makeTexture(descriptor: shadowTexture) else { throw ArenaRendererError.outOfMemory }

        self.device = device
        self.queue = queue
        self.backgroundPipeline = try pipeline("backgroundVertex", "backgroundFragment")
        self.groundPipeline = try pipeline("groundVertex", "groundFragment")
        self.bonePipeline = try pipeline("boneVertex", "boneFragment")
        self.dotPipeline = try pipeline("dotVertex", "dotFragment", blended: true)
        self.shadowPipeline = try device.makeRenderPipelineState(descriptor: shadowDescriptor)
        self.depthState = try depthState(compare: .less, write: true)
        self.noDepthState = try depthState(compare: .always, write: false)
        self.overlayDepthState = try depthState(compare: .lessEqual, write: false)
        self.shadowMap = shadowMap
        self.keneiMesh = try Self.makeMesh(device: device, halfExtents: GameTuning.Bone.keneiHalfExtents, cornerRadius: GameTuning.Bone.keneiCornerRadius)
        self.saqaMesh = try Self.makeMesh(device: device, halfExtents: GameTuning.Bone.saqaHalfExtents, cornerRadius: GameTuning.Bone.saqaCornerRadius)

        for _ in 0..<Self.framesInFlight {
            guard let bones = device.makeBuffer(length: Self.maxBones * MemoryLayout<BoneInstance>.stride, options: .storageModeShared),
                  let dots = device.makeBuffer(length: Self.maxDots * MemoryLayout<DotInstance>.stride, options: .storageModeShared)
            else { throw ArenaRendererError.outOfMemory }
            boneBuffers.append(bones)
            dotBuffers.append(dots)
        }
    }

    private static func makeMesh(device: MTLDevice, halfExtents: SIMD3<Float>, cornerRadius: Float) throws -> Mesh {
        let mesh = BoneMesh.roundedBox(halfExtents: halfExtents, cornerRadius: cornerRadius)
        guard let vertices = device.makeBuffer(bytes: mesh.vertices, length: mesh.vertices.count * MemoryLayout<BoneVertex>.stride, options: .storageModeShared),
              let indices = device.makeBuffer(bytes: mesh.indices, length: mesh.indices.count * MemoryLayout<UInt16>.stride, options: .storageModeShared)
        else { throw ArenaRendererError.outOfMemory }
        return Mesh(vertices: vertices, indices: indices, indexCount: mesh.indices.count, extents: SIMD4(halfExtents, cornerRadius))
    }

    func draw(_ scene: Scene, in layer: CAMetalLayer) {
        guard scene.camera.viewportSize.width > 0 else { return }
        inFlight.wait()
        guard let drawable = layer.nextDrawable(),
              let commandBuffer = queue.makeCommandBuffer(),
              let targets = renderTargets(matching: drawable.texture)
        else {
            inFlight.signal()
            return
        }
        let semaphore = inFlight
        commandBuffer.addCompletedHandler { _ in semaphore.signal() }

        bufferIndex = (bufferIndex + 1) % Self.framesInFlight
        let boneBuffer = boneBuffers[bufferIndex]
        let dotBuffer = dotBuffers[bufferIndex]

        // One buffer, three runs: kenei, field saqas, hand saqa.
        let kenei = Array(scene.kenei.prefix(Self.maxBones))
        let saqa = Array(scene.saqa.prefix(Self.maxBones - kenei.count))
        let hand = Array(scene.hand.prefix(Self.maxBones - kenei.count - saqa.count))
        let pointer = boneBuffer.contents().bindMemory(to: BoneInstance.self, capacity: Self.maxBones)
        for (index, instance) in (kenei + saqa + hand).enumerated() {
            pointer[index] = instance
        }
        let dots = Array(scene.dots.prefix(Self.maxDots))
        let dotPointer = dotBuffer.contents().bindMemory(to: DotInstance.self, capacity: Self.maxDots)
        for (index, dot) in dots.enumerated() {
            dotPointer[index] = dot
        }

        var frame = frameUniforms(for: scene)

        // Shadows: bones on the field only.
        let shadowPass = MTLRenderPassDescriptor()
        shadowPass.depthAttachment.texture = shadowMap
        shadowPass.depthAttachment.loadAction = .clear
        shadowPass.depthAttachment.clearDepth = 1
        shadowPass.depthAttachment.storeAction = .store
        if let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: shadowPass) {
            encoder.setRenderPipelineState(shadowPipeline)
            encoder.setDepthStencilState(depthState)
            // Back faces into the map: lit faces can't shadow themselves (no acne).
            encoder.setCullMode(.front)
            encoder.setFrontFacing(.counterClockwise)
            encoder.setDepthBias(2, slopeScale: 2.5, clamp: 0.01)
            encoder.setVertexBytes(&frame, length: MemoryLayout<FrameUniforms>.stride, index: 1)
            encoder.setVertexBuffer(boneBuffer, offset: 0, index: 2)
            drawBones(keneiMesh, count: kenei.count, firstInstance: 0, encoder: encoder)
            drawBones(saqaMesh, count: saqa.count, firstInstance: kenei.count, encoder: encoder)
            encoder.endEncoding()
        }

        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = targets.color
        pass.colorAttachments[0].resolveTexture = drawable.texture
        pass.colorAttachments[0].loadAction = .dontCare
        pass.colorAttachments[0].storeAction = .multisampleResolve
        pass.depthAttachment.texture = targets.depth
        pass.depthAttachment.loadAction = .clear
        pass.depthAttachment.clearDepth = 1
        pass.depthAttachment.storeAction = .dontCare
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: pass) else {
            commandBuffer.commit()
            return
        }
        encoder.setVertexBytes(&frame, length: MemoryLayout<FrameUniforms>.stride, index: 1)
        encoder.setFragmentBytes(&frame, length: MemoryLayout<FrameUniforms>.stride, index: 1)
        encoder.setFragmentTexture(shadowMap, index: 0)

        // The haze behind everything; it covers every pixel, so no clear is needed.
        encoder.setRenderPipelineState(backgroundPipeline)
        encoder.setDepthStencilState(noDepthState)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)

        encoder.setRenderPipelineState(groundPipeline)
        encoder.setDepthStencilState(depthState)
        var field = scene.field.packed()
        encoder.setFragmentBytes(&field, length: field.count * MemoryLayout<SIMD4<Float>>.stride, index: 2)
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)

        encoder.setRenderPipelineState(bonePipeline)
        encoder.setCullMode(.back)
        encoder.setFrontFacing(.counterClockwise)
        encoder.setVertexBuffer(boneBuffer, offset: 0, index: 2)
        drawBones(keneiMesh, count: kenei.count, firstInstance: 0, encoder: encoder)
        drawBones(saqaMesh, count: saqa.count + hand.count, firstInstance: kenei.count, encoder: encoder)

        if !dots.isEmpty {
            encoder.setRenderPipelineState(dotPipeline)
            encoder.setDepthStencilState(overlayDepthState)
            encoder.setCullMode(.none)
            encoder.setVertexBuffer(dotBuffer, offset: 0, index: 2)
            var viewport = SIMD2<Float>(Float(drawable.texture.width), Float(drawable.texture.height))
            encoder.setVertexBytes(&viewport, length: MemoryLayout<SIMD2<Float>>.stride, index: 3)
            encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4, instanceCount: dots.count)
        }

        encoder.endEncoding()
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }

    private func drawBones(_ mesh: Mesh, count: Int, firstInstance: Int, encoder: MTLRenderCommandEncoder) {
        guard count > 0 else { return }
        var extents = mesh.extents
        encoder.setVertexBuffer(mesh.vertices, offset: 0, index: 0)
        encoder.setFragmentBytes(&extents, length: MemoryLayout<SIMD4<Float>>.stride, index: 3)
        encoder.drawIndexedPrimitives(
            type: .triangle,
            indexCount: mesh.indexCount,
            indexType: .uint16,
            indexBuffer: mesh.indices,
            indexBufferOffset: 0,
            instanceCount: count,
            baseVertex: 0,
            baseInstance: firstInstance
        )
    }

    private func frameUniforms(for scene: Scene) -> FrameUniforms {
        let camera = scene.camera
        let viewProjection = camera.viewProjection
        let light = GameTuning.Light.self

        // Snap the shadow map to whole texels so shadows don't crawl as the camera moves.
        let texel = 2 * light.shadowHalfExtent / Float(light.shadowMapSize)
        var focus = scene.shadowFocus
        focus.x = (focus.x / texel).rounded() * texel
        focus.z = (focus.z / texel).rounded() * texel
        focus.y = 0
        let lightView = simd_float4x4.lookAt(eye: focus + light.direction * 12, target: focus, up: [0, 0, -1])
        let lightProjection = simd_float4x4.orthographic(halfWidth: light.shadowHalfExtent, halfHeight: light.shadowHalfExtent, near: 0.5, far: 30)

        return FrameUniforms(
            viewProjection: viewProjection,
            inverseViewProjection: viewProjection.inverse,
            lightViewProjection: lightProjection * lightView,
            cameraPosition: SIMD4(camera.eye.value, scene.time),
            lightDirection: SIMD4(light.direction, light.intensity),
            lightColor: SIMD4(1.0, 0.96, 0.9, 0),
            sky: SIMD4(0.96, 0.94, 0.92, light.ambient),
            bounce: SIMD4(Palette.felt.linear * 1.3, 0),
            haze: SIMD4(Palette.haze.linear, 0.02),
            zenith: SIMD4(Palette.zenith.linear, 0),
            stage: SIMD4(0, 3, 9, 22),
            shadow: SIMD4(1 / Float(light.shadowMapSize), 0.0001, 0.85, 0)
        )
    }

    /// MSAA color and depth live only in tile memory: never written out, so they cost nothing.
    private func renderTargets(matching drawable: MTLTexture) -> (color: MTLTexture, depth: MTLTexture)? {
        if let targets, targets.color.width == drawable.width, targets.color.height == drawable.height {
            return targets
        }
        func target(_ format: MTLPixelFormat) -> MTLTexture? {
            let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: format, width: drawable.width, height: drawable.height, mipmapped: false)
            descriptor.textureType = .type2DMultisample
            descriptor.sampleCount = Self.sampleCount
            descriptor.usage = .renderTarget
            #if targetEnvironment(simulator)
            descriptor.storageMode = .private
            #else
            descriptor.storageMode = .memoryless
            #endif
            return device.makeTexture(descriptor: descriptor)
        }
        guard let color = target(Self.pixelFormat), let depth = target(Self.depthFormat) else { return nil }
        targets = (color, depth)
        return targets
    }
}
