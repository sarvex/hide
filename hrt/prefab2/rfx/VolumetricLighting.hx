package hrt.prefab2.rfx;

class VolumetricLightingShader extends hrt.shader.PbrShader {

	static var SRC = {
		@param var bottom : Float;
		@param var top : Float;
		@param var fallOff : Float;

		@param var shadowMap : Sampler2D;
		@param var shadowProj : Mat3x4;
		@param var shadowBias : Float;
		@param var lightDir : Vec3;
		@param var angleThreshold : Float;

		@param var brightOpacity : Float;
		@param var darkOpacity : Float;
		@param var darkColor : Vec3;
		@param var brightColor : Vec3;
		@param var lightColor : Vec3;
		@param var gamma : Float;

		@param var cameraInverseViewProj : Mat4;
		@param var cameraPosition : Vec3;

		@const @param var steps : Int;

		@param var ditheringNoise : Sampler2D;
		@param var ditheringIntensity : Float;
		@param var targetSize : Vec2;
		@param var ditheringSize : Vec2;
		@const var USE_DITHERING : Bool;

		function computeScattering(rayDir : Vec3) : Float {
			var G_SCATTERING = 1.0;
			var d = dot(rayDir, lightDir);
			var res = 1.0 - d * d;
			res = res / 4.0 * PI * pow(1.0 + G_SCATTERING * G_SCATTERING - 2.0 * G_SCATTERING * d, 1.5);
			return res;
		}

		function getFogDensity(z : Float) : Float {
			return smoothstep(0.0, 1.0, (top - z) / (top - fallOff));
		}

		function fragment() {
			var origin = getPosition();
			var amount = 0.;

			var toCam = normalize(cameraPosition - origin);
			origin += saturate(bottom - origin.z) / toCam.z * toCam;
			var density = saturate((top - origin.z) / (top - bottom));
			var d = (top - origin.z) / toCam.z;
			if ( USE_DITHERING ) {
				var dithering = ditheringNoise.getLod(calculatedUV * targetSize / ditheringSize, 0.0).r;
				dithering *= ditheringIntensity * d / steps;
				origin += toCam * dithering;
			}
			var end = origin + d * toCam;

			var fog = 0.0;
			for ( i in 1...steps ) {
				var pos = mix(origin, end, float(i) / float(steps));

				var shadowPos = pos * shadowProj;
				var zMax = shadowPos.z.saturate();
				var shadowUv = screenToUv(shadowPos.xy);
				var shadowDepth = shadowMap.getLod(shadowUv.xy, 0.0).r;

				// TODO : Mie scattering approximation
				var scattering = computeScattering(toCam);
				fog += zMax - shadowBias > shadowDepth ? 0.0 : getFogDensity(pos.z) / float(steps);
			}

			var color = mix(darkColor, brightColor, fog) * lightColor;
			density *= mix(darkOpacity, brightOpacity, fog);


			pixelColor = vec4(color, density);
		}
	};
}

class VolumetricLighting extends RendererFX {

	var pass = new h3d.pass.ScreenFx(new VolumetricLightingShader());
	var blurPass = new h3d.pass.Blur();

	@:s public var gamma : Float = 1.0;
	@:s public var bottom : Float = 0.0;
	@:s public var top : Float = 10.0;
	@:s public var fallOff : Float = 0.8;
	@:s public var steps : Int = 10;
	@:s public var textureSize : Float = 0.5;
	@:s public var blur : Float = 0.5;

	@:s public var angleThreshold : Float = 90.0;
	@:s public var darkOpacity : Float = 0.0;
	@:s public var brightOpacity : Float = 1.0;
	@:s public var darkColor : Int = 0;
	@:s public var brightColor : Int = 0xFFFFFF;

	@:s public var ditheringNoise : String;
	@:s public var ditheringIntensity : Float = 1.0;

	override function makeInstance( ctx : hrt.prefab2.Prefab.InstanciateContext ) : Void {
		super.makeInstance(ctx);
		updateInstance();
	}

	override function begin(r:h3d.scene.Renderer, step:h3d.impl.RendererFX.Step) {
		if( step == BeforeTonemapping ) {
			r.mark("VolumetricLighting");

			var sun = Std.downcast(r.getLightSystem().shadowLight, h3d.scene.pbr.DirLight);
			if ( sun == null || sun.shadows == null || !sun.shadows.enabled )
				return;
			var tex = r.allocTarget("volumetricLighting", false, textureSize, RGBA16F);
			tex.clear(0, 0.0);
			r.ctx.engine.pushTarget(tex);

			pass.shader.gamma = gamma;
			pass.shader.bottom = bottom;
			pass.shader.top = top;
			pass.shader.fallOff = bottom + (top - bottom) * fallOff;

			pass.shader.darkColor = h3d.Vector.fromColor(darkColor);
			pass.shader.brightColor = h3d.Vector.fromColor(brightColor);
			pass.shader.lightColor.set(hxd.Math.pow(sun.color.x, gamma), hxd.Math.pow(sun.color.y, gamma), hxd.Math.pow(sun.color.z, gamma));
			var lightDir = sun.getAbsPos().front();
			lightDir.normalize();
			pass.shader.lightDir.load(lightDir);
			var cosAngle = Math.cos(hxd.Math.degToRad(angleThreshold));
			pass.shader.angleThreshold = Math.cos(hxd.Math.degToRad(angleThreshold));

			var camFront = r.ctx.camera.target.sub(r.ctx.camera.pos);
			camFront.normalize();
			var dot = camFront.dot(lightDir);
			dot = hxd.Math.clamp(dot);
			var alignedFactor = (1.0 - dot) / (1.0 - cosAngle);
			alignedFactor = hxd.Math.clamp(alignedFactor);
			pass.shader.brightOpacity = brightOpacity * alignedFactor;
			pass.shader.darkOpacity = darkOpacity * alignedFactor;

			pass.shader.cameraInverseViewProj = r.ctx.camera.getInverseViewProj();
			pass.shader.shadowMap = sun.shadows.getShadowTex();
			pass.shader.shadowProj = sun.shadows.getShadowProj();
			pass.shader.cameraPosition = r.ctx.camera.pos;
			pass.shader.steps = steps;
			pass.shader.ditheringIntensity = ditheringIntensity;
			pass.shader.ditheringNoise = ditheringNoise != null ? hxd.res.Loader.currentInstance.load(ditheringNoise).toTexture() : h3d.mat.Texture.fromColor(0);
			pass.shader.ditheringNoise.wrap = Repeat;
			if ( ditheringNoise != null )
				pass.shader.USE_DITHERING = true;
			else
				pass.shader.USE_DITHERING = false;
			pass.shader.targetSize.set(tex.width, tex.height);
			pass.shader.ditheringSize.set(pass.shader.ditheringNoise.width, pass.shader.ditheringNoise.height);
			pass.pass.setBlendMode(Alpha);
			pass.setGlobals(r.ctx);
			pass.render();

			r.ctx.engine.popTarget();

			if ( blur > 0.0 ) {
				blurPass.radius = blur;
				blurPass.apply(r.ctx, tex);
			}

			var pbrRenderer = Std.downcast(r, h3d.scene.pbr.Renderer);
			h3d.pass.Copy.run(tex, r.ctx.getGlobal("hdrMap"), Add);
		}
	}

	#if editor

	override function edit( ctx : hide.prefab2.EditContext ) {
		super.edit(ctx);
		ctx.properties.add(new hide.Element(
			'<div class="group" name="Fog">
				<dl>
					<dt>Bottom</dt><dd><input type="range" min="0" max="10" field="bottom"/></dd>
					<dt>Top</dt><dd><input type="range" min="0" max="10" field="top"/></dd>
					<dt>Falloff</dt><dd><input type="range" min="0" max="1" field="fallOff"/></dd>
					<dt>Steps</dt><dd><input type="range" step="1" min="0" max="255" field="steps"/></dd>
					<dt>Texture size</dt><dd><input type="range" min="0" max="1" field="textureSize"/></dd>
					<dt>Blur</dt><dd><input type="range" step="1" min="0" max="100" field="blur"/></dd>
					<dt>Blue noise</dt><dd><input type="texturepath" field="ditheringNoise"/></dd>
					<dt>Dithering intensity</dt><dd><input type="range" min="0" max="1" field="ditheringIntensity"/></dd>
				</dl>
			</div>
			<div class="group" name="Color">
				<dt>Angle threshold</dt><dd><input type="range" min="0" max="180" field="angleThreshold"/></dd>
				<dt>Dark opacity</dt><dd><input type="range" min="0" max="1" field="darkOpacity"/></dd>
				<dt>Bright opacity</dt><dd><input type="range" min="0" max="1" field="brightOpacity"/></dd>
				<dt>Dark color</dt><dd><input type="color" field="darkColor"/></dd>
				<dt>Bright color</dt><dd><input type="color" field="brightColor"/></dd>
				<dt>Gamma</dt><dd><input type="range" min="1" max="2" field="gamma"/></dd>
			</div>
			'), this, function(pname) {
				ctx.onChange(this, pname);
		});
	}

	#end

	static var _ = Prefab.register("rfx.volumetricLighting", VolumetricLighting);

}