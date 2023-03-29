package hrt.prefab2;

import hrt.impl.Gradient;
import hrt.impl.TextureType;
import hide.prefab2.HideProps;

typedef ShaderDef = {
	var shader : hxsl.SharedShader;
	var inits : Array<{ variable : hxsl.Ast.TVar, value : Dynamic }>;
}

class Shader extends Prefab {

	@:s var targetMaterial : String;
	@:s var recursiveApply = true;

	static var shaderCache : Map<String, ShaderDef> = new Map<String, ShaderDef>();

	public var shader : hxsl.Shader;

	function new(?parent) {
		super(parent);
		props = {};
	}

	public function makeShader() : hxsl.Shader {
		return null;
	}

	public function getShaderDefinition() : hxsl.SharedShader {
		var s = shader != null ? shader : makeShader();
		return s == null ? null : @:privateAccess s.shader;
	}

	override function updateInstance(?propName) {
		var shaderDef = getShaderDefinition();
		if( shader == null || shaderDef == null )
			return;
		syncShaderVars(shader, shaderDef);
	}

	function syncShaderVars( shader : hxsl.Shader, shaderDef : hxsl.SharedShader ) {
		for(v in shaderDef.data.vars) {
			if(v.kind != Param)
				continue;
			var val : Dynamic = Reflect.field(props, v.name);
			switch(v.type) {
			case TVec(_, VFloat):
				if(val != null) {
					if( Std.isOfType(val,Int) ) {
						var v = new h3d.Vector();
						v.setColor(val);
						val = v;
					} else
						val = h3d.Vector.fromArray(val);
				} else
					val = new h3d.Vector();
			case TSampler2D:
				if( val != null ) {
					val = Utils.getTextureFromValue(val);
				}
				else {
					var childNoise = getOpt(hrt.prefab2.l2d.NoiseGenerator, v.name);
					if(childNoise != null)
						val = childNoise.toTexture();
				}
			default:
			}
			if(val == null)
				continue;
			setShaderParam(shader,v,val);
		}
	}

	function setShaderParam( shader:hxsl.Shader, v : hxsl.Ast.TVar, value : Dynamic ) {
		Reflect.setProperty(shader, v.name, value);
	}

	function applyShader( obj : h3d.scene.Object, material : h3d.mat.Material, shader : hxsl.Shader ) {
		material.mainPass.addShader(shader);
	}

	public function loadShader( path : String ) : ShaderDef {
		var r = shaderCache.get(path);
		if(r != null)
			return r;
		var cl : Class<hxsl.Shader> = cast Type.resolveClass(path.split("/").join("."));
		if(cl == null) return null;
		// make sure to share the SharedShader instance with the real shader
		// so we don't get a duplicate cache of instances
		var shaderInst = Type.createEmptyInstance(cl);
		@:privateAccess shaderInst.initialize();
		var shader = @:privateAccess shaderInst.shader;
		r = {
			shader: shader,
			inits: []
		};
		shaderCache.set(path, r);
		return r;
	}

	function iterMaterials(callb) {
		var parent = getRoot();

		if( Std.isOfType(parent, Material) ) {
			var material : Material = cast parent;
			for( m in material.getMaterials() )
				callb(null, m);
		} else {
			var objs;
			if( recursiveApply ) {
				objs = [];
				for( c in parent.flatten() ) {
					var l3d = c.getLocal3d();
					if (l3d != null)
						objs.push(l3d);
				}

			} else if( parent.type == "object" ) {
				// apply to all immediate children
				objs = [];
				for( c in parent.children ) {
					var l3d = c.getLocal3d();
					if (l3d != null)
						objs.push(l3d);
				}
			} else
			{
				throw "implement getObjects";
				// objs = shared.getObjects(parent, h3d.scene.Object);
			}
			for( obj in objs )
				for( m in obj.getMaterials(false) )
					callb(obj, m);
		}
	}

	override function onMakeInstance(?o2d: h2d.Object = null, ?o3d: h3d.scene.Object = null) {
		var shader = makeShader();
		if( shader == null )
			return;
		var local2d = o2d;
		if( local2d != null ) {
			var drawable = Std.downcast(local2d, h2d.Drawable);
			if (drawable != null) {
				drawable.addShader(shader);
			} else {
				var flow = Std.downcast(local2d, h2d.Flow);
				if (flow != null) {
					@:privateAccess if (flow.background != null) {
						flow.background.addShader(shader);
					}
				}
			}
		}
		var local3d = o3d;
		if( local3d != null )
			iterMaterials(function(obj,mat) if( targetMaterial == null || targetMaterial == mat.name ) applyShader(obj, mat, shader));
		this.shader = shader;
		updateInstance();
	}

	override function onDestroy() {
		var drawable = Std.downcast(getLocal2d(), h2d.Drawable);
		if (drawable != null) {
			drawable.removeShader(shader);
		}
	}

	#if editor

	function getEditProps(shaderDef: hxsl.SharedShader) : Array<hrt.prefab.Props.PropDef> {
		var props = [];
		for(v in shaderDef.data.vars) {
			if( v.kind != Param )
				continue;
			if( v.qualifiers != null && v.qualifiers.contains(Ignore) )
				continue;
			var prop = makeShaderParam(v);
			if( prop == null ) continue;
			props.push({name: v.name, t: prop});
		}
		return props;
	}

	override function edit( ectx : hide.prefab2.EditContext ) {
		super.edit(ectx);

		var shaderDef = getShaderDefinition();
		if( shaderDef == null)
			return;

		var propGroup = new hide.Element('<div class="group" name="Properties">
			<dl>
				<dt>Apply recursively</dt><dd><input type="checkbox" field="recursiveApply"/></dd>
			</dl>
		</div>');
		var materials = [];
		iterMaterials(function(_,m) if( m.name != null && materials.indexOf(m.name) < 0 ) materials.push(m.name));
		if( targetMaterial != null && materials.indexOf(targetMaterial) < 0 )
			materials.push(targetMaterial);
		if( materials.length >= 2 || targetMaterial != null ) {
			propGroup.append(new hide.Element('
			<dl>
				<dt>Material</dt>
				<dd>
					<select field="targetMaterial">
						<option value="">All</option>
						${[for( m in materials ) '<option value="$m"${targetMaterial == m ? " selected":""}>$m</option>'].join("")}
					</select>
				</dd>
			</dl>'));
		}
		ectx.properties.add(propGroup, this, function(pname) {
			if( targetMaterial == "" ) targetMaterial = null;
			ectx.onChange(this, pname);
		});

		var group = new hide.Element('<div class="group" name="Shader"></div>');
		var props = getEditProps(shaderDef);
		group.append(hide.comp.PropsEditor.makePropsList(props));
		ectx.properties.add(group,this.props, function(pname) {
			ectx.onChange(this, pname);

			// Notify change to FX in case param is used by curves
			var fx = getParent(hrt.prefab2.fx.FX);
			if(fx != null)
				ectx.rebuildPrefab(fx, true);
		});
	}

	function makeShaderParam( v : hxsl.Ast.TVar ) : hrt.prefab.Props.PropType {
		var min : Null<Float> = null, max : Null<Float> = null;
		if( v.qualifiers != null )
			for( q in v.qualifiers )
				switch( q ) {
				case Range(rmin, rmax): min = rmin; max = rmax;
				default:
				}
		return switch( v.type ) {
		case TInt:
			PInt(min == null ? null : Std.int(min), max == null ? null : Std.int(max));
		case TFloat:
			PFloat(min != null ? min : 0.0, max != null ? max : 1.0);
		case TBool:
			PBool;
		case TSampler2D:
			PTexture;
		case TVec(n, VFloat):
			PVec(n);
		default:
			PUnsupported(hxsl.Ast.Tools.toString(v.type));
		}
	}

	override function getHideProps() : HideProps {
		var cl = Type.getClass(this);
		var name = Type.getClassName(cl).split(".").pop();
		return {
			icon : "cog",
			name : name,
			fileSource : cl == hrt.prefab2.DynamicShader ? ["hx"] : null,
			allowParent : function(p) return p.to(Object2D) != null || p.to(Object3D) != null || p.to(Material) != null
		};
	}

	#end

}