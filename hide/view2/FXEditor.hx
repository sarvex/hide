package hide.view2;
import hide.view.FileTree;
import hrt.prefab2.Light;
using Lambda;

import hide.Element;
import hrt.prefab2.Prefab in PrefabElement;
import hrt.prefab2.Curve;
import hrt.prefab2.fx.Event;
import hide.view2.CameraController.CamController;

typedef PropTrackDef = {
    name: String,
    ?def: Float
};

@:access(hide.view2.FXEditor)
class FXEditContext extends hide.prefab2.EditContext {
    var parent : FXEditor;
    public function new(parent) {
        super();
        this.parent = parent;
    }
    override function onChange(p, propName) {
        super.onChange(p, propName);
        parent.onPrefabChange(p, propName);
    }
}

@:access(hide.view2.FXEditor)
private class FXSceneEditor extends hide.comp2.SceneEditor {
    var parent : hide.view2.FXEditor;
    public function new(view,  data) {
        super(view, data);
        parent = cast view;
    }

    override function onSceneReady() {
        super.onSceneReady();
        parent.onSceneReady();
    }

    override function onPrefabChange(p: PrefabElement, ?pname: String) {
        super.onPrefabChange(p, pname);
        parent.onPrefabChange(p, pname);
    }

    override function update(dt) {
        super.update(dt);
        parent.onUpdate(dt);
    }

    override function duplicate(thenMove : Bool) {
        var elements = selectedPrefabs;
        if(elements == null || elements.length == 0)
            return;
        if( isDuplicating )
            return;
        isDuplicating = true;
        if( gizmo.moving ) {
            @:privateAccess gizmo.finishMove();
        }
        var undoes = [];
        var newElements = [];
        for(elt in elements) {
            var clone = elt.make(elt.parent);
            var index = elt.parent.children.indexOf(elt) + 1;
            elt.parent.children.remove(clone);
            elt.parent.children.insert(index, clone);
            autoName(clone);
            newElements.push(clone);

            undoes.push(function(undo) {
                if(undo) elt.parent.children.remove(clone);
                else elt.parent.children.insert(index, clone);
            });
        }
        refresh(Full, function() {
            selectElements(newElements);
            tree.setSelection(newElements);
            if(thenMove && curEdit.rootObjects.length > 0) {
                gizmo.startMove(MoveXY, true);
                gizmo.onFinishMove = function() {
                    refreshProps();
                }
            }
            isDuplicating = false;
        });
        refreshParents(elements);

        undo.change(Custom(function(undo) {
            selectElements([], NoHistory);

            var fullRefresh = false;
            if(undo) {
                for(elt in newElements) {
                    if(!removeInstance(elt)) {
                        fullRefresh = true;
                        break;
                    }
                }
            }

            for(u in undoes) u(undo);

            if(!undo) {
                for(elt in newElements)
                    makePrefab(elt);
            }

            refresh(fullRefresh ? Full : Partial);
        }));
    }

    // TODO(ces) : restore
    override function createDroppedElement(path:String, parent:PrefabElement):PrefabElement {
        throw "implement";
        /*var type = Prefab.getPrefabType(path);
        if(type == "fx") {
            var relative = ide.makeRelative(path);
            var ref = new hrt.prefab2.fx.SubFX(parent);
            ref.path = relative;
            ref.name = new haxe.io.Path(relative).file;
            return ref;
        }
        return super.createDroppedElement(path, parent);*/
    }

    override function setElementSelected( p : PrefabElement, b : Bool ) {
        if( p.getParent(hrt.prefab2.fx.Emitter) != null )
            return false;
        return super.setElementSelected(p, b);
    }

    override function selectElements( elts, ?mode ) {
        super.selectElements(elts, mode);
        parent.onSelect(elts);
    }

    override function refresh(?mode, ?callb:Void->Void) {
        // Always refresh scene
        refreshScene();
        refreshTree(callb);
        parent.onRefreshScene();
    }

    override function getNewContextMenu(current: PrefabElement, ?onMake: PrefabElement->Void=null, ?groupByType = true ) {
        if(current != null && current.to(hrt.prefab2.Shader) != null) {
            var ret : Array<hide.comp.ContextMenu.ContextMenuItem> = [];
            ret.push({
                label: "Animation",
                menu: parent.getNewTrackMenu(current)
            });
            return ret;
        }
        var allTypes = super.getNewContextMenu(current, onMake, false);
        var recents = getNewRecentContextMenu(current, onMake);

        var menu = [];
        if (parent.is2D) {
            for(name in ["Group 2D", "Bitmap", "Anim2D", "Atlas", "Particle2D", "Text", "Shader", "Shader Graph", "Placeholder"]) {
                var item = allTypes.find(i -> i.label == name);
                if(item == null) continue;
                allTypes.remove(item);
                menu.push(item);
            }
            if(current != null) {
                menu.push({
                    label: "Animation",
                    menu: parent.getNewTrackMenu(current)
                });
            }
        } else {
            for(name in ["Group", "Polygon", "Model", "Shader", "Emitter", "Trails"]) {
                var item = allTypes.find(i -> i.label == name);
                if(item == null) continue;
                allTypes.remove(item);
                menu.push(item);
            }
            if(current != null) {
                menu.push({
                    label: "Animation",
                    menu: parent.getNewTrackMenu(current)
                });
            }

            menu.push({
                label: "Material",
                menu: [
                    getNewTypeMenuItem("material", current, onMake, "Default"),
                    getNewTypeMenuItem("material", current, function (p) {
                        // TODO: Move material presets to props.json
                        p.props = {
                            PBR: {
                                mode: "BeforeTonemapping",
                                blend: "Alpha",
                                shadows: false,
                                culling: "Back",
                                colorMask: 0xff
                            }
                        }
                        if(onMake != null) onMake(p);
                    }, "Unlit")
                ]
            });
            menu.sort(function(l1,l2) return Reflect.compare(l1.label,l2.label));
        }

        var events = allTypes.filter(i -> StringTools.endsWith(i.label, "Event"));
        if(events.length > 0) {
            menu.push({
                label: "Events",
                menu: events
            });
            for(e in events)
                allTypes.remove(e);
        }

        menu.push({label: null, isSeparator: true});
        menu.push({
            label: "Other",
            menu: allTypes
        });
        menu.unshift({
            label : "Recents",
            menu : recents,
        });
        return menu;
    }

    override function getAvailableTags(p:PrefabElement) {
        return cast ide.currentConfig.get("fx.tags");
    }
}

class FXEditor extends hide.view.FileView {

    var sceneEditor : FXSceneEditor;
    var data : hrt.prefab2.fx.BaseFX;
    var is2D : Bool = false;
    var tabs : hide.comp.Tabs;
    var fxprops : hide.comp.PropsEditor;

    var tools : hide.comp.Toolbar;
    var treePanel : hide.comp.ResizablePanel;
    var animPanel : hide.comp.ResizablePanel;
    var light : h3d.scene.fwd.DirLight;
    var lightDirection = new h3d.Vector( 1, 2, -4 );

    var scene(get, null):  hide.comp2.Scene;
    function get_scene() return sceneEditor.scene;
    var properties(get, null):  hide.comp.PropsEditor;
    function get_properties() return sceneEditor.properties;

    // autoSync
    var autoSync : Bool;
    var currentVersion : Int = 0;
    var lastSyncChange : Float = 0.;
    var showGrid = true;
    var grid : h3d.scene.Graphics;
    var grid2d : h2d.Graphics;

    var lastPan : h2d.col.Point;

    var timelineLeftMargin = 10;
    var xScale = 200.;
    var xOffset = 0.;

    var pauseButton : hide.comp.Toolbar.ToolToggle;
    var currentTime : Float;
    var selectMin : Float;
    var selectMax : Float;
    var previewMin : Float;
    var previewMax : Float;
    var curveEdits : Array<hide.comp2.CurveEditor>;
    var timeLineEl : Element;
    var afterPanRefreshes : Array<Bool->Void> = [];
    var statusText : h2d.Text;

    var scriptEditor : hide.comp.ScriptEditor;
    //var fxScriptParser : hrt.prefab2.fx.FXScriptParser;
    var cullingPreview : h3d.scene.Sphere;

	var viewModes : Array<String>;

    override function getDefaultContent() {
        return haxe.io.Bytes.ofString(ide.toJSON(new hrt.prefab2.fx.FX().serializeToDynamic()));
    }

    override function canSave() {
        return data != null;
    }

    override function save() {
        if( !canSave() )
            return;
        var content = ide.toJSON(data.serializeToDynamic());
        var newSign = ide.makeSignature(content);
        if(newSign != currentSign)
            haxe.Timer.delay(saveBackup.bind(content), 0);
        currentSign = newSign;
        sys.io.File.saveContent(getPath(), content);
        super.save();
    }

    override function onDisplay() {
        if( sceneEditor != null ) sceneEditor.dispose();
        currentTime = 0.;
        xOffset = -timelineLeftMargin / xScale;
        var content = sys.io.File.getContent(getPath());
        var json = haxe.Json.parse(content);
        /*if (json.type == "fx") {
            var inf = hrt.prefab2.Library.getRegistered().get("fx");
            data = Std.downcast(Type.createInstance(inf.cl, null), hrt.prefab2.fx.FX);
            if ( data == null )
                throw "fx prefab override failed";
        }
        else {
            // TODO(ces) : Fix FX2D
            //is2D = true;
            //data = new hrt.prefab2.fx.FX2D();
            throw "FX2D not handled yet";
        }*/
        data = Std.downcast(PrefabElement.createFromDynamic(json), hrt.prefab2.fx.BaseFX);
        currentSign = ide.makeSignature(content);

        element.html('
            <div class="flex vertical">
                <div style="flex: 0 0 30px;">
                    <span class="tools-buttons"></span>
                </div>
                <div class="scene-partition" style="display: flex; flex-direction: row; flex: 1; overflow: hidden;">
                    <div style="display: flex; flex-direction: column; flex: 1; overflow: hidden;">
                        <div class="flex heaps-scene"></div>
                        <div class="fx-animpanel">
                            <div class="top-bar">
                                <div class="timeline">
                                    <div class="timeline-scroll"/></div>
                                </div>
                            </div>
                            <div class="anim-scroll"></div>
                            <div class="overlay-container">
                                <div class="overlay"></div>
                            </div>
                        </div>
                    </div>
                    <div class="tree-column">
                        <div class="flex vertical">
                            <div class="hide-toolbar" style="zoom: 80%">
                                <div class="button collapse-btn" title="Collapse all">
                                    <div class="icon ico ico-reply-all"></div>
                                </div>
                            </div>
                            <div class="hide-scenetree"></div>
                        </div>
                    </div>
                    <div class="tabs">
                        <div class="tab expand" name="Scene" icon="sitemap">
                            <div class="hide-scroll"></div>
                        </div>
                        <div class="tab expand" name="Properties" icon="cog">
                            <div class="fx-props"></div>
                        </div>
                        <div class="tab expand" name="Script" icon="cog">
                            <div class="fx-script"></div>
                            <div class="fx-scriptParams"></div>
                        </div>
                    </div>
                </div>
            </div>');
        tools = new hide.comp.Toolbar(null,element.find(".tools-buttons"));
        tabs = new hide.comp.Tabs(null,element.find(".tabs"));
        sceneEditor = new FXSceneEditor(this, data);
        element.find(".hide-scenetree").first().append(sceneEditor.tree.element);
        element.find(".hide-scroll").first().append(sceneEditor.properties.element);
        element.find(".heaps-scene").first().append(sceneEditor.scene.element);

        var treeColumn = element.find(".tree-column").first();
        treePanel = new hide.comp.ResizablePanel(Horizontal, treeColumn);
        treePanel.saveDisplayKey = "treeColumn";
        treePanel.onResize = () -> @:privateAccess if( scene.window != null) scene.window.checkResize();

        var fxPanel = element.find(".fx-animpanel").first();
        animPanel = new hide.comp.ResizablePanel(Vertical, fxPanel);
        animPanel.saveDisplayKey = "animPanel";
        animPanel.onResize = () -> @:privateAccess if( scene.window != null) scene.window.checkResize();

        refreshLayout();
        element.resize(function(e) {
            refreshTimeline(false);
            rebuildAnimPanel();
        });
        element.find(".collapse-btn").click(function(e) {
            sceneEditor.collapseTree();
        });
        fxprops = new hide.comp.PropsEditor(undo,null,element.find(".fx-props"));
        {
            var edit = new FXEditContext(this);
            edit.properties = fxprops;
            edit.scene = sceneEditor.scene;
            edit.cleanups = [];
            data.edit(edit);
        }

        if (is2D) {
            sceneEditor.camera2D = true;
        }

        var scriptElem = element.find(".fx-script");
        scriptEditor = new hide.comp.ScriptEditor(data.scriptCode, null, scriptElem, scriptElem);
        function onSaveScript() {
            data.scriptCode = scriptEditor.code;
            save();
            skipNextChange = true;
            modified = false;
        }
        scriptEditor.onSave = onSaveScript;
        //fxScriptParser = new hrt.prefab2.fx.FXScriptParser();
        data.scriptCode = scriptEditor.code;

        keys.register("playPause", function() { pauseButton.toggle(!pauseButton.isDown()); });

        currentVersion = undo.currentID;
        sceneEditor.tree.element.addClass("small");

        var timeline = element.find(".timeline");
        var sMin = 0.0;
        var sMax = 0.0;
        timeline.contextmenu(function(e) {
            var offset = e.clientX - timeline.offset().left;
            var marker = data.markers.find(m -> hxd.Math.abs(offset - xt(m.t)) < 4);
            new hide.comp.ContextMenu([
            { label : "Add marker", click : function() {
                if(data.markers == null)
                    data.markers = [];
                var prevVal = data.markers.copy();
                data.markers.push({t : ixt(e.clientX - timeline.offset().left)});
                undo.change(Field(data, "markers", prevVal), refreshTimeline.bind(false));
                refreshTimeline(false);
            } },
            { label : "Remove marker", enabled: marker != null, click : function() {
                var prevVal = data.markers.copy();
                data.markers.remove(marker);
                undo.change(Field(data, "markers", prevVal), refreshTimeline.bind(false));
                refreshTimeline(false);
            } }
            ]);
            e.preventDefault();
            return false;
        });
        timeline.mousedown(function(e) {
            var lastX = e.clientX;
            var shift = e.shiftKey;
            var ctrl = e.ctrlKey;
            var xoffset = timeline.offset().left;
            var clickTime = ixt(e.clientX - xoffset);

            if(shift) {
                sMin = hxd.Math.max(0, clickTime);
            }
            else if(ctrl) {
                previewMin = hxd.Math.max(0, clickTime);
            }

            function updateMouse(e: js.jquery.Event) {
                var dt = (e.clientX - lastX) / xScale;
                if(e.which == 2) {
                    xOffset -= dt;
                    xOffset = hxd.Math.max(xOffset, -timelineLeftMargin/xScale);
                }
                else if(e.which == 1) {
                    if(shift) {
                        sMax = ixt(e.clientX - xoffset);
                    }
                    else if(ctrl) {
                        previewMax = ixt(e.clientX - xoffset);
                    }
                    else {
                        if(!pauseButton.isDown())
                            pauseButton.toggle(true);
                        currentTime = ixt(e.clientX - xoffset);
                        currentTime = hxd.Math.max(currentTime, 0);
                    }
                }

                if(hxd.Math.abs(sMax - sMin) < 1e-5) {
                    selectMin = 0;
                    selectMax = 0;
                }
                else {
                    selectMax = hxd.Math.max(sMin, sMax);
                    selectMin = hxd.Math.min(sMin, sMax);
                }
            }

            if(data.markers != null) {
                var marker = data.markers.find(m -> hxd.Math.abs(xt(clickTime) - xt(m.t)) < 4);
                if(marker != null) {
                    var prevVal = marker.t;
                    startDrag(function(e) {
                        updateMouse(e);
                        var x = ixt(e.clientX - xoffset);
                        x = hxd.Math.max(0, x);
                        x = untyped parseFloat(x.toFixed(5));
                        marker.t = x;
                        refreshTimeline(true);
                    }, function(e) {
                        undo.change(Field(marker, "t", prevVal), refreshTimeline.bind(false));
                    });
                    e.preventDefault();
                    e.stopPropagation();
                    return;
                }
            }

            element.mousemove(function(e: js.jquery.Event) {
                updateMouse(e);
                lastX = e.clientX;
                refreshTimeline(true);
                afterPan(true);
            });
            element.mouseup(function(e: js.jquery.Event) {
                updateMouse(e);

                if(previewMax < previewMin + 0.1) {
                    previewMin = 0;
                    previewMax = data.duration == 0 ? 5000 : data.duration;
                }

                element.off("mousemove");
                element.off("mouseup");
                e.preventDefault();
                e.stopPropagation();
                refreshTimeline(false);
                afterPan(false);
            });
            e.preventDefault();
            e.stopPropagation();
        });

        var wheelTimer : haxe.Timer = null;
        timeline.on("mousewheel", function(e) {
            var step = e.originalEvent.wheelDelta > 0 ? 1.0 : -1.0;
            xScale *= Math.pow(1.125, step);
            e.preventDefault();
            e.stopPropagation();
            refreshTimeline(false);
            if(wheelTimer != null)
                wheelTimer.stop();
            wheelTimer = haxe.Timer.delay(function() {
                for(ce in curveEdits) {
                    ce.xOffset = xOffset;
                    ce.xScale = xScale;
                    ce.refresh();
                }
                afterPan(false);
            }, 50);
        });

        selectMin = 0.0;
        selectMax = 0.0;
        previewMin = 0.0;
        previewMax = data.duration == 0 ? 5000 : data.duration;
        refreshTimeline(false);
    }

    function refreshLayout() {
        if (animPanel != null) animPanel.setSize();
        if (treePanel != null) treePanel.setSize();
    }

    override function onActivate() {
        if( sceneEditor != null )
            refreshLayout();
    }

	public function onSceneReady() {
		light = sceneEditor.scene.s3d.find(function(o) return Std.downcast(o, h3d.scene.fwd.DirLight));
		if( light == null ) {
			light = new h3d.scene.fwd.DirLight(scene.s3d);
			light.enableSpecular = true;
		} else
			light = null;

		var axis = new h3d.scene.Graphics(scene.s3d);
		axis.z = 0.001;
		axis.lineStyle(2,0xFF0000); axis.lineTo(1,0,0);
		axis.lineStyle(1,0x00FF00); axis.moveTo(0,0,0); axis.lineTo(0,1,0);
		axis.lineStyle(1,0x0000FF); axis.moveTo(0,0,0); axis.lineTo(0,0,1);
		axis.lineStyle();
		axis.material.mainPass.setPassName("debuggeom");
		axis.visible = (!is2D) ? showGrid : false;

		cullingPreview = new h3d.scene.Sphere(0xffffff, data.cullingRadius, true, scene.s3d);
		cullingPreview.visible = (!is2D) ? showGrid : false;

		var toolsDefs = new Array<hide.comp.Toolbar.ToolDef>();
		toolsDefs.push({id: "perspectiveCamera", title : "Perspective camera", icon : "video-camera", type : Button(() -> sceneEditor.resetCamera()) });
		toolsDefs.push({id: "camSettings", title : "Camera Settings", icon : "camera", type : Popup((e : hide.Element) -> new hide.comp2.CameraControllerEditor(sceneEditor, null,e)) });

		toolsDefs.push({id: "", title : "", icon : "", type : Separator});

		toolsDefs.push({id: "translationMode", title : "Gizmo translation Mode", icon : "arrows", type : Button(@:privateAccess sceneEditor.gizmo.translationMode)});
		toolsDefs.push({id: "rotationMode", title : "Gizmo rotation Mode", icon : "refresh", type : Button(@:privateAccess sceneEditor.gizmo.rotationMode)});
		toolsDefs.push({id: "scalingMode", title : "Gizmo scaling Mode", icon : "expand", type : Button(@:privateAccess sceneEditor.gizmo.scalingMode)});

        toolsDefs.push({id: "", title : "", icon : "", type : Separator});

        toolsDefs.push({id: "toggleSnap", title : "Snap Toggle", icon: "magnet", type : Toggle((v) -> {sceneEditor.snapToggle = v; sceneEditor.updateGrid();})});
        toolsDefs.push({id: "snap-menu", title : "", icon: "", type : Popup((e) -> new hide.comp2.SceneEditor.SnapSettingsPopup(null, e, sceneEditor))});

		toolsDefs.push({id: "", title : "", icon : "", type : Separator});

		toolsDefs.push({id: "localTransformsToggle", title : "Local transforms", icon : "compass", type : Toggle((v) -> sceneEditor.localTransform = v)});
		
		toolsDefs.push({id: "", title : "", icon : "", type : Separator});

		toolsDefs.push({id: "gridToggle", title : "Toggle grid", icon : "th", type : Toggle((v) -> { showGrid = v; updateGrid(); }) });
		toolsDefs.push({id: "axisToggle", title : "Toggle model axis", icon : "cube", type : Toggle((v) -> { sceneEditor.showBasis = v; sceneEditor.updateBasis(); }) });
		toolsDefs.push({id: "iconVisibility", title : "Toggle 3d icons visibility", icon : "image", type : Toggle((v) -> { hide.Ide.inst.show3DIcons = v; }), defaultValue: true });


		tools.saveDisplayKey = "FXScene/tools";
		/*tools.addButton("video-camera", "Perspective camera", () -> sceneEditor.resetCamera());
		tools.addSeparator();
		tools.addButton("arrows", "Gizmo translation Mode", @:privateAccess sceneEditor.gizmo.translationMode, () -> {
			var items = [{
				label : "Snap to Grid",
				click : function() {
					@:privateAccess sceneEditor.gizmo.snapToGrid = !sceneEditor.gizmo.snapToGrid;
				},
				checked: @:privateAccess sceneEditor.gizmo.snapToGrid
			}];
			var steps : Array<Float> = sceneEditor.view.config.get("sceneeditor.gridSnapSteps");
			for (step in steps) {
				items.push({
					label : ""+step,
					click : function() {
						@:privateAccess sceneEditor.gizmo.moveStep = step;
					},
					checked: @:privateAccess sceneEditor.gizmo.moveStep == step
				});
			}
			new hide.comp.ContextMenu(items);
		});
		tools.addButton("refresh", "Gizmo rotation Mode", @:privateAccess sceneEditor.gizmo.rotationMode, () -> {
			var steps : Array<Float> = sceneEditor.view.config.get("sceneeditor.rotateStepCoarses");
			var items = [{
				label : "Snap enabled",
				click : function() {
					@:privateAccess sceneEditor.gizmo.rotateSnap = !sceneEditor.gizmo.rotateSnap;
				},
				checked: @:privateAccess sceneEditor.gizmo.rotateSnap
			}];
			for (step in steps) {
				items.push({
					label : ""+step+"°",
					click : function() {
						@:privateAccess sceneEditor.gizmo.rotateStepCoarse = step;
					},
					checked: @:privateAccess sceneEditor.gizmo.rotateStepCoarse == step
				});
			}
			new hide.comp.ContextMenu(items);
		});
		tools.addButton("expand", "Gizmo scaling Mode", @:privateAccess sceneEditor.gizmo.scalingMode);

		tools.addSeparator();


		function renderProps() {
			properties.clear();
			var renderer = scene.s3d.renderer;
			var group = new Element('<div class="group" name="Renderer"></div>');
			renderer.editProps().appendTo(group);
			properties.add(group, renderer.props, function(_) {
				renderer.refreshProps();
				if( !properties.isTempChange ) renderProps();
			});
			var lprops = {
				power : Math.sqrt(light.color.r),
				enable: true
			};
			var group = new Element('<div class="group" name="Light">
				<dl>
				<dt>Power</dt><dd><input type="range" min="0" max="4" field="power"/></dd>
				</dl>
			</div>');
			properties.add(group, lprops, function(_) {
				var p = lprops.power * lprops.power;
				light.color.set(p, p, p);
			});
		}
		tools.addButton("gears", "Renderer Properties", renderProps);

		tools.addToggle("th", "Show grid", function(v) {
			showGrid = v;
			axis.visible = (is2D) ? false : v;
			cullingPreview.visible = (is2D) ? false : v;
			updateGrid();
		}, showGrid);


		tools.addToggle("cube", "Toggle model axis", null, (v) -> { sceneEditor.showBasis = v; sceneEditor.updateBasis(); });

		tools.addToggle("image", "Toggle 3d icons visibility", null, function(v) { hide.Ide.inst.show3DIcons = v; }, true);
		tools.addColor("Background color", function(v) {
			scene.engine.backgroundColor = v;
			updateGrid();
		}, scene.engine.backgroundColor);
		tools.addToggle("refresh", "Auto synchronize", function(b) {
			autoSync = b;
		});
		tools.addToggle("compass", "Local transforms", (v) -> sceneEditor.localTransform = v, sceneEditor.localTransform);
		tools.addToggle("connectdevelop", "Wireframe",(b) -> { sceneEditor.setWireframe(b); });
		pauseButton = tools.addToggle("pause", "Pause animation", function(v) {}, false);
		tools.addRange("Speed", function(v) {
			scene.speed = v;
		}, scene.speed);*/

		tools.makeToolbar(toolsDefs, config, keys);

		function renderProps() {
			properties.clear();
			var renderer = scene.s3d.renderer;
			var group = new Element('<div class="group" name="Renderer"></div>');
			renderer.editProps().appendTo(group);
			properties.add(group, renderer.props, function(_) {
				renderer.refreshProps();
				if( !properties.isTempChange ) renderProps();
			});
			var lprops = {
				power : Math.sqrt(light.color.r),
				enable: true
			};
			var group = new Element('<div class="group" name="Light">
				<dl>
				<dt>Power</dt><dd><input type="range" min="0" max="4" field="power"/></dd>
				</dl>
			</div>');
			properties.add(group, lprops, function(_) {
				var p = lprops.power * lprops.power;
				light.color.set(p, p, p);
			});
		}
		tools.addButton("gears", "Renderer Properties", renderProps);
		tools.addToggle("refresh", "Auto synchronize", function(b) {
			autoSync = b;
		});

		tools.addToggle("connectdevelop", "Wireframe",(b) -> { sceneEditor.setWireframe(b); });

		tools.addColor("Background color", function(v) {
			scene.engine.backgroundColor = v;
			updateGrid();
		}, scene.engine.backgroundColor);

		tools.addSeparator();

		var viewModesMenu = tools.addMenu(null, "View Modes");
		var items : Array<hide.comp.ContextMenu.ContextMenuItem> = [];
		viewModes = ["LIT", "Full", "Albedo", "Normal", "Roughness", "Metalness", "Emissive", "AO", "Shadows", "Performance"];
		for(typeid in viewModes) {
			items.push({label : typeid, click : function() {
				var r = Std.downcast(scene.s3d.renderer, h3d.scene.pbr.Renderer);
				if ( r == null )
					return;
				var slides = @:privateAccess r.slides;
				if ( slides == null )
					return;
				switch(typeid) {
				case "LIT":
					r.displayMode = Pbr;
				case "Full":
					r.displayMode = Debug;
					slides.shader.mode = Full;
				case "Albedo":
					r.displayMode = Debug;
					slides.shader.mode = Albedo;
				case "Normal":
					r.displayMode = Debug;
					slides.shader.mode = Normal;
				case "Roughness":
					r.displayMode = Debug;
					slides.shader.mode = Roughness;
				case "Metalness":
					r.displayMode = Debug;
					slides.shader.mode = Metalness;
				case "Emissive":
					r.displayMode = Debug;
					slides.shader.mode = Emmissive;
				case "AO":
					r.displayMode = Debug;
					slides.shader.mode = AO;
				case "Shadows":
						r.displayMode = Debug;
						slides.shader.mode = Shadow;
				case "Performance":
					r.displayMode = Performance;
				default:
				}
			}
			});
		}
		viewModesMenu.setContent(items);//, {id: "viewModes", title : "View Modes", type : Menu(filtersToMenuItem(viewModes, "View"))});
		var el = viewModesMenu.element;
		el.addClass("View Modes");

		tools.addSeparator();


		pauseButton = tools.addToggle("pause", "Pause animation", function(v) {}, false, "play");
		tools.addRange("Speed", function(v) {
			scene.speed = v;
		}, scene.speed);

		var gizmo = @:privateAccess sceneEditor.gizmo;

		var onSetGizmoMode = function(mode: hide.view2.l3d.Gizmo.EditMode) {
			tools.element.find("#translationMode").get(0).toggleAttribute("checked", mode == Translation);
			tools.element.find("#rotationMode").get(0).toggleAttribute("checked", mode == Rotation);
			tools.element.find("#scalingMode").get(0).toggleAttribute("checked", mode == Scaling);
		};

		gizmo.onChangeMode = onSetGizmoMode;
		onSetGizmoMode(gizmo.editMode);



		statusText = new h2d.Text(hxd.res.DefaultFont.get(), scene.s2d);
		statusText.setPosition(5, 5);

		updateGrid();
	}

    // public function onSceneReady() {
    //     light = sceneEditor.scene.s3d.find(function(o) return Std.downcast(o, h3d.scene.fwd.DirLight));
    //     if( light == null ) {
    //         light = new h3d.scene.fwd.DirLight(scene.s3d);
    //         light.enableSpecular = true;
    //     } else
    //         light = null;

    //     var axis = new h3d.scene.Graphics(scene.s3d);
    //     axis.z = 0.001;
    //     axis.lineStyle(2,0xFF0000); axis.lineTo(1,0,0);
    //     axis.lineStyle(1,0x00FF00); axis.moveTo(0,0,0); axis.lineTo(0,1,0);
    //     axis.lineStyle(1,0x0000FF); axis.moveTo(0,0,0); axis.lineTo(0,0,1);
    //     axis.lineStyle();
    //     axis.material.mainPass.setPassName("debuggeom");
    //     axis.visible = (!is2D) ? showGrid : false;

    //     cullingPreview = new h3d.scene.Sphere(0xffffff, data.cullingRadius, true, scene.s3d);
    //     cullingPreview.visible = (!is2D) ? showGrid : false;

    //     tools.saveDisplayKey = "FXScene/tools";
    //     tools.addButton("video-camera", "Perspective camera", () -> sceneEditor.resetCamera());
    //     tools.addButton("arrows", "Gizmo translation Mode", @:privateAccess sceneEditor.gizmo.translationMode, () -> {
    //         var items = [{
    //             label : "Snap to Grid",
    //             click : function() {
    //                 @:privateAccess sceneEditor.gizmo.snapToGrid = !sceneEditor.gizmo.snapToGrid;
    //             },
    //             checked: @:privateAccess sceneEditor.gizmo.snapToGrid
    //         }];
    //         var steps : Array<Float> = sceneEditor.view.config.get("sceneeditor.gridSnapSteps");
    //         for (step in steps) {
    //             items.push({
    //                 label : ""+step,
    //                 click : function() {
    //                     @:privateAccess sceneEditor.gizmo.moveStep = step;
    //                 },
    //                 checked: @:privateAccess sceneEditor.gizmo.moveStep == step
    //             });
    //         }
    //         new hide.comp.ContextMenu(items);
    //     });
    //     tools.addButton("undo", "Gizmo rotation Mode", @:privateAccess sceneEditor.gizmo.rotationMode, () -> {
    //         var steps : Array<Float> = sceneEditor.view.config.get("sceneeditor.rotateStepCoarses");
    //         var items = [{
    //             label : "Snap enabled",
    //             click : function() {
    //                 @:privateAccess sceneEditor.gizmo.rotateSnap = !sceneEditor.gizmo.rotateSnap;
    //             },
    //             checked: @:privateAccess sceneEditor.gizmo.rotateSnap
    //         }];
    //         for (step in steps) {
    //             items.push({
    //                 label : ""+step+"°",
    //                 click : function() {
    //                     @:privateAccess sceneEditor.gizmo.rotateStepCoarse = step;
    //                 },
    //                 checked: @:privateAccess sceneEditor.gizmo.rotateStepCoarse == step
    //             });
    //         }
    //         new hide.comp.ContextMenu(items);
    //     });
    //     tools.addButton("compress", "Gizmo scaling Mode", @:privateAccess sceneEditor.gizmo.scalingMode);

    //     function renderProps() {
    //         properties.clear();
    //         var renderer = scene.s3d.renderer;
    //         var group = new Element('<div class="group" name="Renderer"></div>');
    //         renderer.editProps().appendTo(group);
    //         properties.add(group, renderer.props, function(_) {
    //             renderer.refreshProps();
    //             if( !properties.isTempChange ) renderProps();
    //         });
    //         var lprops = {
    //             power : Math.sqrt(light.color.r),
    //             enable: true
    //         };
    //         var group = new Element('<div class="group" name="Light">
    //             <dl>
    //             <dt>Power</dt><dd><input type="range" min="0" max="4" field="power"/></dd>
    //             </dl>
    //         </div>');
    //         properties.add(group, lprops, function(_) {
    //             var p = lprops.power * lprops.power;
    //             light.color.set(p, p, p);
    //         });
    //     }
    //     tools.addButton("gears", "Renderer Properties", renderProps);

    //     tools.addToggle("th", "Show grid", function(v) {
    //         showGrid = v;
    //         axis.visible = (is2D) ? false : v;
    //         cullingPreview.visible = (is2D) ? false : v;
    //         updateGrid();
    //     }, showGrid);


    //     tools.addToggle("cube", "Toggle model axis", null, (v) -> { sceneEditor.showBasis = v; sceneEditor.updateBasis(); });

    //     tools.addToggle("image", "Toggle 3d icons visibility", null, function(v) { hide.Ide.inst.show3DIcons = v; }, true);
    //     tools.addColor("Background color", function(v) {
    //         scene.engine.backgroundColor = v;
    //         updateGrid();
    //     }, scene.engine.backgroundColor);
    //     tools.addToggle("refresh", "Auto synchronize", function(b) {
    //         autoSync = b;
    //     });
    //     tools.addToggle("compass", "Local transforms", (v) -> sceneEditor.localTransform = v, sceneEditor.localTransform);
    //     tools.addToggle("connectdevelop", "Wireframe",(b) -> { sceneEditor.setWireframe(b); });
    //     pauseButton = tools.addToggle("pause", "Pause animation", function(v) {}, false);
    //     tools.addRange("Speed", function(v) {
    //         scene.speed = v;
    //     }, scene.speed);

    //     statusText = new h2d.Text(hxd.res.DefaultFont.get(), scene.s2d);
    //     statusText.setPosition(5, 5);

    //     updateGrid();
    // }

    function onPrefabChange(p: PrefabElement, ?pname: String) {
        if(p == data) {
            previewMax = hxd.Math.min(data.duration == 0 ? 5000 : data.duration, previewMax);
            refreshTimeline(false);

            cullingPreview.radius = data.cullingRadius;
        }

        if(pname == "time") {
            afterPan(false);
            data.refreshObjectAnims();
        }
    }

    function onRefreshScene() {
        var renderProps = data.find(e -> e.to(hrt.prefab2.RenderProps));
        if(renderProps != null)
            renderProps.applyProps(scene.s3d.renderer);
        updateGrid();
    }

    override function onDragDrop(items : Array<String>, isDrop : Bool) {
        return sceneEditor.onDragDrop(items,isDrop);
    }

    function onSelect(elts : Array<PrefabElement>) {
        rebuildAnimPanel();
    }

    inline function xt(x: Float) return Math.round((x - xOffset) * xScale);
    inline function ixt(px: Float) return px / xScale + xOffset;

    function refreshTimeline(anim: Bool) {
        var scroll = element.find(".timeline-scroll");
        scroll.empty();
        var width = scroll.parent().width();
        var minX = Math.floor(ixt(0));
        var maxX = Math.ceil(hxd.Math.min(data.duration == 0 ? 5000 : data.duration, ixt(width)));
        for(ix in minX...(maxX+1)) {
            var mark = new Element('<span class="mark"></span>').appendTo(scroll);
            mark.css({left: xt(ix)});
            mark.text(ix + ".00");
        }

        var overlay = element.find(".overlay");
        overlay.empty();
        timeLineEl = new Element('<span class="time-marker"></span>').appendTo(overlay);
        timeLineEl.css({left: xt(currentTime)});

        if(data.markers != null) {
            for(m in data.markers) {
                var el = new Element('<span class="marker"></span>').appendTo(overlay);
                el.css({left: xt(m.t)});
            }
        }

        var select = new Element('<span class="selection"></span>').appendTo(overlay);
        select.css({left: xt(selectMin), width: xt(selectMax) - xt(selectMin)});

        if(!anim && selectMax != selectMin) {
            var selLeft = new Element('<span class="selection-left"></span>').appendTo(overlay);
            var selRight = new Element('<span class="selection-right"></span>').appendTo(overlay);

            function updateSelectPos() {
                select.css({left: xt(selectMin), width: xt(selectMax) - xt(selectMin)});
                selLeft.css({left: xt(selectMin) - 4});
                selRight.css({left: xt(selectMax)});
            }
            updateSelectPos();

            function refreshViews() {
                for(ce in curveEdits) {
                    ce.refreshGraph(false);
                    ce.onChange(false);
                }
            }

            var curves = null;
            var allKeys = null;

            function updateSelected() {
                curves = [];
                var anyNonEmitter = curveEdits.find(ce -> !isInstanceCurve(ce.curve)) != null;
                for(ce in curveEdits) {
                    if(anyNonEmitter && isInstanceCurve(ce.curve))
                        continue;  // Filter-out emitter curves unless only emitter curves are selected
                    curves.push(ce.curve);
                }

                allKeys = [];
                for(curve in curves) {
                    for(key in curve.keys) {
                        if(key.time >= selectMin && key.time <= selectMax)
                            allKeys.push(key);
                    }
                }
            }

            var backup = null;
            var prevSel = null;

            function beforeChange() {
                backup = [for(c in curves) haxe.Json.parse(haxe.Json.stringify(c.save({})))];
                prevSel = [selectMin, selectMax];
            }

            function afterChange() {
                var newVals = [for(c in curves) haxe.Json.parse(haxe.Json.stringify(c.save({})))];
                var newSel = [selectMin, selectMax];
                undo.change(Custom(function(undo) {
                    if(undo) {
                        for(i in 0...curves.length)
                            curves[i].load(backup[i]);
                        selectMin = prevSel[0];
                        selectMax = prevSel[1];
                    }
                    else {
                        for(i in 0...curves.length)
                            curves[i].load(newVals[i]);
                        selectMin = newSel[0];
                        selectMax = newSel[1];
                    }
                    updateSelected();
                    updateSelectPos();
                    refreshViews();
                }));
                refreshViews();
            }

            var duplicateMode = false;
            var previewKeys = [];
            function setupSelectDrag(element: js.jquery.JQuery, update: Float->Float->Void) {
                element.mousedown(function(e) {
                    updateSelected();

                    if(e.button != 0)
                        return;
                    var offset = scroll.offset();
                    e.preventDefault();
                    e.stopPropagation();
                    var lastTime = ixt(e.clientX);
                    beforeChange();
                    startDrag(function(e) {
                        var time = ixt(e.clientX);
                        update(time, lastTime);
                        for(ce in curveEdits) {
                            ce.refreshGraph(true);
                            ce.onChange(true);
                        }
                        updateSelectPos();
                        lastTime = time;
                    }, function(e) {
                        for (pKey in previewKeys) {
                            var curve = curves.find((curve) -> return curve.previewKeys.contains(pKey));
                            curve.previewKeys.remove(pKey);
                        }
                        previewKeys = [];
                        for(ce in curveEdits) {
                            ce.refreshGraph(true);
                            ce.onChange(true);
                        }
                        afterChange();
                    }, function(e) {
                        if (e.keyCode == hxd.Key.ALT){
                            if (!duplicateMode) {
                                duplicateMode = !duplicateMode;
                                for (key in allKeys) {
                                    var curve = curves.find((curve) -> return curve.keys.contains(key));
                                    var pKey = curve.addPreviewKey(key.time, key.value);
                                    previewKeys.push(pKey);
                                }
                                allKeys = [];
                                for(ce in curveEdits) {
                                    ce.refreshGraph(true);
                                    ce.onChange(true);
                                }
                            }
                        }
                    }, function(e) {
                        if (e.keyCode == hxd.Key.ALT){
                            if (duplicateMode) {
                                duplicateMode = !duplicateMode;
                                for (pKey in previewKeys) {
                                    var curve = curves.find((curve) -> return curve.previewKeys.contains(pKey));
                                    curve.previewKeys.remove(pKey);
                                    allKeys.push(curve.addKey(pKey.time, pKey.value));
                                }
                                previewKeys = [];
                                for(ce in curveEdits) {
                                    ce.refreshGraph(true);
                                    ce.onChange(true);
                                }
                            }
                        }
                    });
                });
            }

            setupSelectDrag(selRight, function(time, lastTime) {
                var shift = time - lastTime;
                if(selectMax > selectMin + 0.1) {
                    var scaleFactor = (selectMax + shift - selectMin) / (selectMax - selectMin);

                    if (duplicateMode) {
                        for (key in previewKeys)
                            key.time = (key.time - selectMin) * scaleFactor + selectMin;
                    }
                    else {
                        for(key in allKeys)
                            key.time = (key.time - selectMin) * scaleFactor + selectMin;
                    }

                    selectMax += shift;
                }
            });

            setupSelectDrag(selLeft, function(time, lastTime) {
                var shift = time - lastTime;
                if(selectMax > selectMin + 0.1) {
                    var scaleFactor = (selectMax - (selectMin + shift)) / (selectMax - selectMin);

                    if (duplicateMode) {
                        for(key in previewKeys)
                            key.time = selectMax - (selectMax - key.time) * scaleFactor;
                    }
                    else {
                        for(key in allKeys)
                            key.time = selectMax - (selectMax - key.time) * scaleFactor;
                    }

                    selectMin += shift;
                }
            });

            setupSelectDrag(select, function(time, lastTime) {
                var shift = time - lastTime;

                if (duplicateMode) {
                    for(key in previewKeys)
                        key.time += shift;
                }
                else {
                    for(key in allKeys)
                        key.time += shift;
                }
                selectMin += shift;
                selectMax += shift;

            });
        }

        //var preview = new Element('<span class="preview"></span>').appendTo(overlay);
        // preview.css({left: xt(previewMin), width: xt(previewMax) - xt(previewMin)});
        var prevLeft = new Element('<span class="preview-left"></span>').appendTo(overlay);
        prevLeft.css({left: 0, width: xt(previewMin)});
        var prevRight = new Element('<span class="preview-right"></span>').appendTo(overlay);
        prevRight.css({left: xt(previewMax), width: xt(data.duration == 0 ? 5000 : data.duration) - xt(previewMax)});
    }

    function afterPan(anim: Bool) {
        if(!anim) {
            for(curve in curveEdits) {
                curve.setPan(xOffset, curve.yOffset);
            }
        }
        for(clb in afterPanRefreshes) {
            clb(anim);
        }
    }

    function addCurvesTrack(trackName: String, curves: Array<Curve>, tracksEl: Element) {
        var keyTimeTolerance = 0.05;
        var trackEdits : Array<hide.comp2.CurveEditor> = [];
        var trackEl = new Element('<div class="track">
            <div class="track-header">
                <div class="track-prop">
                    <label>${upperCase(trackName)}</label>
                    <div class="track-toggle"><div class="icon ico"></div></div>
                </div>
                <div class="dopesheet"></div>
            </div>
            <div class="curves"></div>
        </div>');
        if(curves.length == 0)
            return;
        var parent = curves[0].parent;
        var isColorTrack = trackName.toLowerCase().indexOf("color") >= 0 && (curves.length == 3 || curves.length == 4);
        var isColorHSL = isColorTrack && curves.find(c -> StringTools.endsWith(c.name, ".h")) != null;

        var trackToggle = trackEl.find(".track-toggle");
        tracksEl.append(trackEl);
        var curvesContainer = trackEl.find(".curves");
        var trackKey = "trackVisible:" + parent.getAbsPath(true) + "/" + trackName;
        var expand = getDisplayState(trackKey) == true;
        function updateExpanded() {
            var icon = trackToggle.find(".icon");
            if(expand)
                icon.removeClass("ico-angle-right").addClass("ico-angle-down");
            else
                icon.removeClass("ico-angle-down").addClass("ico-angle-right");
            curvesContainer.toggleClass("hidden", !expand);
            for(c in trackEdits)
                c.refresh();
        }
        trackEl.find(".track-prop").click(function(e) {
            expand = !expand;
            saveDisplayState(trackKey, expand);
            updateExpanded();
        });
        var dopesheet = trackEl.find(".dopesheet");
        var evaluator = new hrt.prefab2.fx.Evaluator();

        function getKeyColor(key) {
            return evaluator.getVector(Curve.getColorValue(curves), key.time, new h3d.Vector());
        }

        function dragKey(from: hide.comp2.CurveEditor, prevTime: Float, newTime: Float) {
            for(edit in trackEdits) {
                if(edit == from) continue;
                var k = edit.curve.findKey(prevTime, keyTimeTolerance);
                if(k != null) {
                    newTime = hxd.Math.clamp(newTime, 0.0, edit.curve.maxTime);
                    k.time = newTime;
                    edit.refreshGraph(false, k);
                }
            }
        }
        function refreshCurves(anim: Bool) {
            for(c in trackEdits) {
                c.refreshGraph(anim);
            }
        }

        function refreshKey(key: hide.comp2.CurveEditor.CurveKey, el: Element) {
            if(isColorTrack) {
                var color = getKeyColor(key);
                var colorStr = "#" + StringTools.hex(color.toColor() & 0xffffff, 6);
                el.css({background: colorStr});
            }
        }

        var refreshDopesheet : Void -> Void = null;

        function backupCurves() {
            return [for(c in curves) haxe.Json.parse(haxe.Json.stringify(c.save({})))];
        }
        var lastBackup = backupCurves();

        function beforeChange() {
            lastBackup = backupCurves();
        }

        function afterChange() {
            var newVal = backupCurves();
            var oldVal = lastBackup;
            lastBackup = newVal;
            undo.change(Custom(function(undo) {
                if(undo) {
                    for(i in 0...curves.length)
                        curves[i].load(oldVal[i]);
                }
                else {
                    for(i in 0...curves.length)
                        curves[i].load(newVal[i]);
                }
                lastBackup = backupCurves();
                refreshCurves(false);
                refreshDopesheet();
            }));
            refreshCurves(false);
        }

        function addKey(time: Float) {
            beforeChange();
            for(curve in curves) {
                curve.addKey(time);
            }
            afterChange();
            refreshDopesheet();
        }


        function keyContextClick(key: hrt.prefab2.Curve.CurveKey, el: Element) {
            function setCurveVal(suffix: String, value: Float) {
                var c = curves.find(c -> StringTools.endsWith(c.name, suffix));
                if(c != null) {
                    var k = c.findKey(key.time, keyTimeTolerance);
                    if(k == null) {
                        k = c.addKey(key.time);
                    }
                    k.value = value;
                }
            }

            if(isColorTrack) {
                var picker = new Element("<div></div>").css({
                    "z-index": 100,
                }).appendTo(el);
                var cp = new hide.comp.ColorPicker(false, picker);
                var prevCol = getKeyColor(key);
                cp.value = prevCol.toColor();
                cp.onClose = function() {
                    picker.remove();
                };
                cp.onChange = function(dragging) {
                    if(dragging)
                        return;
                    var col = h3d.Vector.fromColor(cp.value, 1.0);
                    if(isColorHSL) {
                        col = col.toColorHSL();
                        setCurveVal(".h", col.x);
                        setCurveVal(".s", col.y);
                        setCurveVal(".l", col.z);
                        setCurveVal(".a", prevCol.a);
                    }
                    else {
                        setCurveVal(".r", col.x);
                        setCurveVal(".g", col.y);
                        setCurveVal(".b", col.z);
                        setCurveVal(".a", prevCol.a);
                    }
                    refreshCurves(false);
                    refreshKey(key, el);
                };
            }
        }

        refreshDopesheet = function () {
            dopesheet.empty();
            dopesheet.off();
            dopesheet.mouseup(function(e) {
                var offset = dopesheet.offset();
                if(e.ctrlKey) {
                    var x = ixt(e.clientX - offset.left);
                    addKey(x);
                }
            });
            var refKeys = curves[0].keys;
            for(ik in 0...refKeys.length) {
                var key = refKeys[ik];
                var keyEl = new Element('<span class="key">').appendTo(dopesheet);
                function updatePos() keyEl.css({left: xt(refKeys[ik].time)});
                updatePos();
                keyEl.contextmenu(function(e) {
                    keyContextClick(key, keyEl);
                    e.preventDefault();
                    e.stopPropagation();
                });
                keyEl.mousedown(function(e) {
                    var offset = dopesheet.offset();
                    e.preventDefault();
                    e.stopPropagation();
                    if(e.button == 2) {
                    }
                    else {
                        var prevVal = key.time;
                        beforeChange();
                        startDrag(function(e) {
                            var x = ixt(e.clientX - offset.left);
                            x = hxd.Math.max(0, x);
                            var next = refKeys[ik + 1];
                            if(next != null)
                                x = hxd.Math.min(x, next.time - 0.01);
                            var prev = refKeys[ik - 1];
                            if(prev != null)
                                x = hxd.Math.max(x, prev.time + 0.01);
                            dragKey(null, key.time, x);
                            updatePos();
                        }, function(e) {
                            afterChange();
                        });
                    }
                });
                afterPanRefreshes.push(function(anim) {
                    updatePos();
                });
                refreshKey(key, keyEl);
            }
        }

        var minHeight = 40;
        for(curve in curves) {
            var dispKey = getPath() + "/" + curve.getAbsPath(true);
            var curveContainer = new Element('<div class="curve"><label class="curve-label">${curve.name}</alpha></div>').appendTo(curvesContainer);
            var height = getDisplayState(dispKey + "/height");
            if(height == null)
                height = 100;
            if(height < minHeight) height = minHeight;
            curveContainer.height(height);
            curve.maxTime = data.duration == 0 ? 5000 : data.duration;
            var curveEdit = new hide.comp2.CurveEditor(this.undo, curveContainer);
            curveEdit.saveDisplayKey = dispKey;
            curveEdit.lockViewX = true;
            if(curves.length > 1)
                curveEdit.lockKeyX = true;
            if(["visibility", "s", "l", "a"].indexOf(curve.name.split(".").pop()) >= 0) {
                curveEdit.minValue = 0;
                curveEdit.maxValue = 1;
            }
            if(curve.name.indexOf("Rotation") >= 0) {
                curveEdit.minValue = 0;
                curveEdit.maxValue = 360;
            }
            var shader = curve.parent.to(hrt.prefab2.Shader);
            if(shader != null) {
                var sh = shader.getShaderDefinition();
                if(sh != null) {
                    var v = sh.data.vars.find(v -> v.kind == Param && v.name == curve.name);
                    if(v != null && v.qualifiers != null) {
                        for( q in v.qualifiers )
                            switch( q ) {
                            case Range(rmin, rmax):
                                curveEdit.minValue = rmin;
                                curveEdit.maxValue = rmax;
                            default:
                        }
                    }
                }
            }
            curveEdit.xOffset = xOffset;
            curveEdit.xScale = xScale;
            if(isInstanceCurve(curve) && curve.parent.to(hrt.prefab2.fx.Emitter) == null || curve.name.indexOf("inst") >= 0)
                curve.maxTime = 1.0;
            curveEdit.curve = curve;
            curveEdit.onChange = function(anim) {
                refreshDopesheet();
            }

            curveContainer.on("mousewheel", function(e) {
                var step = e.originalEvent.wheelDelta > 0 ? 1.0 : -1.0;
                if(e.ctrlKey) {
                    var prevH = curveContainer.height();
                    var newH = hxd.Math.max(minHeight, prevH + Std.int(step * 20.0));
                    curveContainer.height(newH);
                    saveDisplayState(dispKey + "/height", newH);
                    curveEdit.yScale *= newH / prevH;
                    curveEdit.refresh();
                    e.preventDefault();
                    e.stopPropagation();
                }
            });
            trackEdits.push(curveEdit);
            curveEdits.push(curveEdit);
        }
        refreshDopesheet();
        updateExpanded();
    }

    function addEventsTrack(events: Array<IEvent>, tracksEl: Element) {
        var trackEl = new Element('<div class="track">
            <div class="track-header">
                <div class="track-prop">
                    <label>Events</label>
                </div>
                <div class="events"></div>
            </div>
        </div>');
        var eventsEl = trackEl.find(".events");
        var items : Array<{el: Element, event: IEvent }> = [];
        function refreshItems() {
            var yoff = 1;
            for(item in items) {
                var info = item.event.getDisplayInfo(sceneEditor.curEdit);
                item.el.css({left: xt(item.event.time), top: yoff});
                item.el.width(info.length * xScale);
                item.el.find("label").text(info.label);
                yoff += 21;
            }
            eventsEl.css("height", yoff + 1);
        }

        function refreshTrack() {
            trackEl.remove();
            trackEl = addEventsTrack(events, tracksEl);
        }

        for(event in events) {
            var info = event.getDisplayInfo(sceneEditor.curEdit);
            var evtEl = new Element('<div class="event">
                <i class="icon ico ico-play-circle"></i><label></label>
            </div>').appendTo(eventsEl);
            evtEl.addClass(event.getEventPrefab().type);
            items.push({el: evtEl, event: event });

            var element = event.getEventPrefab();

            evtEl.click(function(e) {
                sceneEditor.showProps(element);
            });

            evtEl.contextmenu(function(e) {
                e.preventDefault();
                e.stopPropagation();
                new hide.comp.ContextMenu([
                    {
                        label: "Delete", click: function() {
                            events.remove(event);
                            sceneEditor.deleteElements([element], refreshTrack);
                        }
                    }
                ]);
            });

            evtEl.mousedown(function(e) {
                var offsetX = e.clientX - xt(event.time);
                e.preventDefault();
                e.stopPropagation();
                if(e.button == 2) {
                }
                else {
                    var prevVal = event.time;
                    startDrag(function(e) {
                        var x = ixt(e.clientX - offsetX);
                        x = hxd.Math.max(0, x);
                        x = untyped parseFloat(x.toFixed(5));
                        event.time = x;
                        refreshItems();
                    }, function(e) {
                        undo.change(Field(event, "time", prevVal), refreshItems);
                    });
                }
            });
        }
        refreshItems();
        afterPanRefreshes.push(function(anim) refreshItems());
        tracksEl.append(trackEl);
        return trackEl;
    }

    function rebuildAnimPanel() {
        if(element == null)
            return;
        var selection = sceneEditor.getSelection();
        var scrollPanel = element.find(".anim-scroll");
        scrollPanel.empty();
        curveEdits = [];
        afterPanRefreshes = [];

        var sections : Array<{
            elt: PrefabElement,
            curves: Array<Curve>,
            events: Array<IEvent>
        }> = [];

        function getSection(elt: PrefabElement) {
            var ctxElt = elt.parent;
            var sect = sections.find(s -> s.elt == ctxElt);
            if(sect == null) {
                sect = {elt: ctxElt, curves: [], events: []};
                sections.push(sect);
            }
            return sect;
        }

        function getTagRec(elt : PrefabElement) {
            var p = elt;
            while(p != null) {
                var tag = sceneEditor.getTag(p);
                if(tag != null)
                    return tag;
                p = p.parent;
            }
            return null;
        }

        for(sel in selection) {
            for(curve in sel.flatten(Curve))
                getSection(curve).curves.push(curve);
            for(evt in sel.flatten(Event))
                getSection(evt).events.push(evt);
            for(fx in sel.flatten(hrt.prefab2.fx.SubFX))
                getSection(fx).events.push(fx);
        }

        for(sec in sections) {
            var objPanel = new Element('<div>
                <div class="tracks-header">
                    <label class="name">${upperCase(sec.elt.name)}</label> <div class="addtrack ico ico-plus-circle"></div>
                    <label class="abspath">${sec.elt.getAbsPath(true)}</label>
                </div>
                <div class="tracks"></div>
            </div>').appendTo(scrollPanel);
            var addTrackEl = objPanel.find(".addtrack");

            var parentTag = getTagRec(sec.elt);
            if(parentTag != null) {
                objPanel.find(".name").css("background", parentTag.color);
            }

            addTrackEl.click(function(e) {
                var menuItems = getNewTrackMenu(sec.elt);
                new hide.comp.ContextMenu(menuItems);
            });
            var tracksEl = objPanel.find(".tracks");

            if(sec.events.length > 0)
                addEventsTrack(sec.events, tracksEl);

            var groups = Curve.getGroups(sec.curves);
            for(group in groups) {
                addCurvesTrack(group.name, group.items, tracksEl);
            }
        }
    }

    function startDrag(onMove: js.jquery.Event->Void, onStop: js.jquery.Event->Void, ?onKeyDown: js.jquery.Event->Void, ?onKeyUp: js.jquery.Event->Void) {
        var el = new Element(element[0].ownerDocument.body);
        var startX = null, startY = null;
        var dragging = false;
        var threshold = 3;
        el.keydown(onKeyDown);
        el.keyup(onKeyUp);
        el.on("mousemove.fxedit", function(e: js.jquery.Event) {
            if(startX == null) {
                startX = e.clientX;
                startY = e.clientY;
            }
            else {
                if(!dragging) {
                    if(hxd.Math.abs(e.clientX - startX) + hxd.Math.abs(e.clientY - startY) > threshold) {
                        dragging = true;
                    }
                }
                if(dragging)
                    onMove(e);
            }
        });
        el.on("mouseup.fxedit", function(e: js.jquery.Event) {
            el.off("mousemove.fxedit");
            el.off("mouseup.fxedit");
            e.preventDefault();
            e.stopPropagation();
            onStop(e);
        });
    }

    function addTracks(element : PrefabElement, props : Array<PropTrackDef>, ?prefix: String) {
        var added = [];
        for(prop in props) {
            var id = prefix != null ? prefix + "." + prop.name : prop.name;
            if(Curve.getCurve(element, id) != null)
                continue;
            var curve = new Curve(element);
            curve.name = id;
            if(prop.def != null)
                curve.addKey(0, prop.def, Linear);
            added.push(curve);
        }

        if(added.length == 0)
            return added;

        undo.change(Custom(function(undo) {
            for(c in added) {
                if(undo)
                    element.children.remove(c);
                else
                    element.children.push(c);
            }
            sceneEditor.refresh();
        }));
        sceneEditor.refresh(function() {
            sceneEditor.selectElements([element]);
        });
        return added;
    }

    public function getNewTrackMenu(elt: PrefabElement) : Array<hide.comp.ContextMenu.ContextMenuItem> {
        var obj3dElt = Std.downcast(elt, hrt.prefab2.Object3D);
        var obj2dElt = Std.downcast(elt, hrt.prefab2.Object2D);
        var shaderElt = Std.downcast(elt, hrt.prefab2.Shader);
        var emitterElt = Std.downcast(elt, hrt.prefab2.fx.Emitter);
        
        // TODO(ces) : Restore
        //var particle2dElt = Std.downcast(elt, hrt.prefab2.l2d.Particle2D);
        var menuItems : Array<hide.comp.ContextMenu.ContextMenuItem> = [];
        var lightElt = Std.downcast(elt, Light);

        inline function hasTrack(pname) {
            return getTrack(elt, pname) != null;
        }

        function trackItem(name: String, props: Array<PropTrackDef>, ?prefix: String) : hide.comp.ContextMenu.ContextMenuItem {
            var hasAllTracks = true;
            for(p in props) {
                if(getTrack(elt, prefix + "." + p.name) == null)
                    hasAllTracks = false;
            }
            return {
                label: upperCase(name),
                click: function() {
                    var added = addTracks(elt, props, prefix);
                },
                enabled: !hasAllTracks };
        }

        function groupedTracks(prefix: String, props: Array<PropTrackDef>) : Array<hide.comp.ContextMenu.ContextMenuItem> {
            var allLabel = [for(p in props) upperCase(p.name)].join("/");
            var ret = [];
            ret.push(trackItem(allLabel, props, prefix));
            for(p in props) {
                var label = upperCase(p.name);
                ret.push(trackItem(label, [p], prefix));
            }
            return ret;
        }

        var hslTracks : Void -> Array<PropTrackDef> = () -> [{name: "h", def: 0.0}, {name: "s", def: 0.0}, {name: "l", def: 1.0}];
        var alphaTrack : Void -> Array<PropTrackDef> = () -> [{name: "a", def: 1.0}];
        var xyzwTracks : Int -> Array<PropTrackDef> = (n) -> [{name: "x"}, {name: "y"}, {name: "z"}, {name: "w"}].slice(0, n);

        if (obj2dElt != null) {
            var scaleTracks = groupedTracks("scale", xyzwTracks(2));
            scaleTracks.unshift(trackItem("Uniform", [{name: "scale"}]));
            menuItems.push({
                label: "Position",
                menu: groupedTracks("position", xyzwTracks(2)),
            });
            menuItems.push({
                label: "Rotation",
                menu: [trackItem("X", [{name: "x"}], "rotation")],
            });
            menuItems.push({
                label: "Scale",
                menu: scaleTracks,
            });
            menuItems.push({
                label: "Color",
                menu: [
                    trackItem("HSL", hslTracks(), "color"),
                    trackItem("Alpha", alphaTrack(), "color")
                ]
            });
            menuItems.push(trackItem("Visibility", [{name: "visibility"}]));
        }
        if(obj3dElt != null) {
            var scaleTracks = groupedTracks("scale", xyzwTracks(3));
            scaleTracks.unshift(trackItem("Uniform", [{name: "scale"}]));
            menuItems.push({
                label: "Position",
                menu: groupedTracks("position", xyzwTracks(3)),
            });
            menuItems.push({
                label: "Rotation",
                menu: groupedTracks("rotation", xyzwTracks(3)),
            });
            menuItems.push({
                label: "Scale",
                menu: scaleTracks,
            });
            menuItems.push({
                label: "Color",
                menu: [
                    trackItem("HSL", hslTracks(), "color"),
                    trackItem("Alpha", alphaTrack(), "color")
                ]
            });
            menuItems.push(trackItem("Visibility", [{name: "visibility"}]));
        }
        if(shaderElt != null) {
            var shader = shaderElt.makeShader();
            var inEmitter = shaderElt.getParent(hrt.prefab2.fx.Emitter) != null;
            var params = shader == null ? [] : @:privateAccess shader.shader.data.vars.filter(inEmitter ? isPerInstance : v -> v.kind == Param);
            for(param in params) {
                var item : hide.comp.ContextMenu.ContextMenuItem = switch(param.type) {
                    case TVec(n, VFloat):
                        var color = param.name.toLowerCase().indexOf("color") >= 0;
                        var label = upperCase(param.name);
                        var menu = null;
                        if(color) {
                            if(n == 3)
                                menu = trackItem(label, hslTracks(), param.name);
                            else if(n == 4)
                                menu = trackItem(label, hslTracks().concat(alphaTrack()), param.name);
                        }
                        if(menu == null)
                            menu = trackItem(label, xyzwTracks(n), param.name);
                        menu;
                    case TFloat:
                        trackItem(upperCase(param.name), [{name: param.name}]);
                    default:
                        null;
                }
                if(item != null)
                    menuItems.push(item);
            }
        }
        function addParam(param : hrt.prefab2.fx.Emitter.ParamDef, prefix: String) {
            var label = prefix + (param.disp != null ? param.disp : upperCase(param.name));
            var item : hide.comp.ContextMenu.ContextMenuItem = switch(param.t) {
                case PVec(n, _):
                    {
                        label: label,
                        menu: groupedTracks(param.name, xyzwTracks(n)),
                    }
                default:
                    trackItem(label, [{name: param.name}]);
            };
            menuItems.push(item);
        }
        if(emitterElt != null) {
            for(param in hrt.prefab2.fx.Emitter.emitterParams) {
                if(!param.animate)
                    continue;
                addParam(param, "");
            }
            for(param in hrt.prefab2.fx.Emitter.instanceParams) {
                if(!param.animate)
                    continue;
                addParam(param, "Instance ");
            }
        }
        // TODO(ces) : Restore
        /*
        if (particle2dElt != null) {
            for(param in hrt.prefab2.l2d.Particle2D.emitter2dParams) {
                if(!param.animate)
                    continue;
                addParam(param, "");
            }
        }*/
        if( lightElt != null ) {
            switch lightElt.kind {
                case Point:
                    menuItems.push({
                        label: "PointLight",
                        menu: [	trackItem("Color", hslTracks(), "color"),
                                trackItem("Power",[{name: "power"}]),
                                trackItem("Size", [{name: "size"}]),
                                trackItem("Range", [{name: "range"}]),
                                ]
                    });
                case Directional:
                    menuItems.push({
                        label: "DirLight",
                        menu: [	trackItem("Color", hslTracks(), "color"),
                                trackItem("Power",[{name: "power"}]),
                                ]
                    });
                case Spot:
                    menuItems.push({
                        label: "SpotLight",
                        menu: [	trackItem("Color", hslTracks(), "color"),
                                trackItem("Power",[{name: "power"}]),
                                trackItem("Range", [{name: "range"}]),
                                trackItem("Angle", [{name: "angle"}]),
                                trackItem("FallOff", [{name: "fallOff"}]),
                                ]
                    });
            }
        }
        return menuItems;
    }

    function isPerInstance( v : hxsl.Ast.TVar ) {
        if( v.kind != Param )
            return false;
        if( v.qualifiers == null )
            return false;
        for( q in v.qualifiers )
            if( q.match(PerInstance(_)) )
                return true;
        return false;
    }

    function updateGrid() {
        if(grid != null) {
            grid.remove();
            grid = null;
        }
        if(grid2d != null) {
            grid2d.remove();
            grid2d = null;
        }

        if(!showGrid)
            return;

        if (is2D) {
            grid2d = new h2d.Graphics(scene.s2d);
            grid2d.scale(1);

            grid2d.lineStyle(1.0, 12632256, 1.0);
            grid2d.moveTo(0, -2000);
            grid2d.lineTo(0, 2000);
            grid2d.moveTo(-2000, 0);
            grid2d.lineTo(2000, 0);
            grid2d.lineStyle(0);

            return;
        }

        grid = new h3d.scene.Graphics(scene.s3d);
        grid.scale(1);
        grid.material.mainPass.setPassName("debuggeom");

        var col = h3d.Vector.fromColor(scene.engine.backgroundColor);
        var hsl = col.toColorHSL();
        if(hsl.z > 0.5) hsl.z -= 0.1;
        else hsl.z += 0.1;
        col.makeColor(hsl.x, hsl.y, hsl.z);

        grid.lineStyle(1.0, col.toColor(), 1.0);
        for(ix in -10...11) {
            grid.moveTo(ix, -10, 0);
            grid.lineTo(ix, 10, 0);
            grid.moveTo(-10, ix, 0);
            grid.lineTo(10, ix, 0);

        }
        grid.lineStyle(0);
    }

    function onUpdate(dt : Float) {
        if (is2D)
            onUpdate2D(dt);
        else
            onUpdate3D(dt);

        @:privateAccess scene.s3d.renderer.ctx.time = currentTime - scene.s3d.renderer.ctx.elapsedTime;
    }

    function onUpdate2D(dt:Float) {
        //TODO(ces) : ...
        throw "not implemented yet";
        /*var anim : hrt.prefab2.fx.FX2D.FX2DAnimation = null;
        if(ctx != null && ctx.local2d != null) {
            anim = Std.downcast(ctx.local2d, hrt.prefab2.fx.FX2D.FX2DAnimation);
        }
        if(!pauseButton.isDown()) {
            currentTime += scene.speed * dt;
            if(timeLineEl != null)
                timeLineEl.css({left: xt(currentTime)});
            if(currentTime >= previewMax) {
                currentTime = previewMin;

                anim.setRandSeed(Std.random(0xFFFFFF));
            }
        }

        if(anim != null) {
            anim.setTime(currentTime);
        }

        if(statusText != null) {
            var lines : Array<String> = [
                'Time: ${Math.round(currentTime*1000)} ms',
                'Scene objects: ${scene.s2d.getObjectsCount()}',
                'Drawcalls: ${h3d.Engine.getCurrent().drawCalls}',
            ];
            statusText.text = lines.join("\n");
        }

        if( autoSync && (currentVersion != undo.currentID || lastSyncChange != properties.lastChange) ) {
            save();
            lastSyncChange = properties.lastChange;
            currentVersion = undo.currentID;
        }

        if (grid2d != null) {
            @:privateAccess grid2d.setPosition(scene.s2d.children[0].x, scene.s2d.children[0].y);
        }

    */
    }

    var avg_smooth = 0.0;
    var trailTime_smooth = 0.0;
    var num_trail_tri_smooth = 0.0;

    public static function floatToStringPrecision(n : Float, ?prec : Int = 2, ?showZeros : Bool = true) {
        if(n == 0) { // quick return
            if (showZeros)
                return "0." + ([for(i in 0...prec) "0"].join(""));
            return "0";
        }
        if (Math.isNaN(n))
            return "NaN";
        if (n >= Math.POSITIVE_INFINITY)
            return "+inf";
        else if (n <= Math.NEGATIVE_INFINITY)
            return "-inf";

        var p = Math.pow(10, prec);
        var fullDec = "";

        if (n > -1. && n < 1) {
            var minusSign:Bool = (n<0.0);
            n = Math.abs(n);
            var val = Math.round(p * n);
            var str = Std.string(val);
            var buf:StringBuf = new StringBuf();
            if (minusSign)
                buf.addChar("-".code);
            for (i in 0...(prec + 1 - str.length))
                buf.addChar("0".code);
            buf.addSub(str, 0);
            fullDec = buf.toString();
        } else {
            var val = Math.round(p * n);
            fullDec = Std.string(val);
        }

        var outStr = fullDec.substr(0, -prec) + '.' + fullDec.substr(fullDec.length - prec, prec);
        if (!showZeros) {
            var i = outStr.length - 1;
            while (i > 0) {
                if (outStr.charAt(i) == "0")
                    outStr = outStr.substr(0, -1);
                else if (outStr.charAt(i) == ".") {
                    outStr = outStr.substr(0, -1);
                    break;
                } else
                    break;
                i--;
            }
        }
        return outStr;
    }

    function onUpdate3D(dt:Float) {
        var local3d = sceneEditor.root3d;
        if(local3d == null)
            return;
            
        var allFx = local3d.findAll(o -> Std.downcast(o, hrt.prefab2.fx.FX.FXAnimation));

        if(!pauseButton.isDown()) {
            currentTime += scene.speed * dt;
            if(timeLineEl != null)
                timeLineEl.css({left: xt(currentTime)});
            if(currentTime >= previewMax) {
                currentTime = previewMin;

                //if(data.scriptCode != null && data.scriptCode.length > 0)
                    //sceneEditor.refreshScene(); // This allow to reset the scene when values are modified causes edition issues, solves
                for(f in allFx)
                    f.setRandSeed(Std.random(0xFFFFFF));
            }
        }

        for(fx in allFx)
            fx.setTime(currentTime - fx.startDelay);
    
        var emitters = local3d.findAll(o -> Std.downcast(o, hrt.prefab2.fx.Emitter.EmitterObject));
        var totalParts = 0;
        for(e in emitters)
            totalParts += @:privateAccess e.numInstances;

        var emitterTime = 0.0;
        for (e in emitters) {
            emitterTime += e.tickTime;
        }

        var trails = local3d.findAll(o -> Std.downcast(o, hrt.prefab2.l3d.Trails.TrailObj));
        var trailCount = 0;
        var trailTime = 0.0;
        var trailTris = 0.0;
        var trailMaxTris = 0;
        var trailMaxLen = 0;
        var trailCalcMaxLen = 0;
        var trailRealIndicies = 0;
        var trailAllocIndicies = 0;


        var poolSize = 0;
        @:privateAccess
        for (trail in trails) {
            for (head in trail.trails) {
                trailCount ++;
                var p = head.firstPoint;
                var len = 0;
                while(p != null) {
                    len ++;
                    p = p.next;
                }
                if (len > trailMaxLen) {
                    trailMaxLen = len;
                }
            }
            trailTime += trail.lastUpdateDuration;
            trailTris += trail.numVerts;

            var p = trail.pool;
            while(p != null) {
                poolSize ++;
                p = p.next;
            }
            trailMaxTris += Std.int(trail.vbuf.length/8.0);
            trailCalcMaxLen = trail.calcMaxTrailPoints();
            trailRealIndicies += trail.numVertsIndices;
            trailAllocIndicies += trail.currentAllocatedIndexCount;
        }

        var smooth_factor = 0.10;
        avg_smooth = avg_smooth * (1.0 - smooth_factor) + emitterTime * smooth_factor;
        trailTime_smooth = trailTime_smooth * (1.0 - smooth_factor) + trailTime * smooth_factor;
        num_trail_tri_smooth = num_trail_tri_smooth * (1.0-smooth_factor) + trailTris * smooth_factor;

        if(statusText != null) {
            var lines : Array<String> = [
                'Time: ${Math.round(currentTime*1000)} ms',
                'Scene objects: ${scene.s3d.getObjectsCount()}',
                'Drawcalls: ${h3d.Engine.getCurrent().drawCalls}',
                'Particles: $totalParts',
                'Particles CPU time: ${floatToStringPrecision(avg_smooth * 1000, 3, true)} ms',
            ];

            if (trailCount > 0) {

                lines.push('Trails CPU time : ${floatToStringPrecision(trailTime_smooth * 1000, 3, true)} ms');

                /*lines.push("---");
                lines.push('Num Trails : $trailCount');
                lines.push('Trails Vertexes : ${floatToStringPrecision(num_trail_tri_smooth, 2, true)}');
                lines.push('Allocated Trails Vertexes : $trailMaxTris');
                lines.push('Max Trail Lenght : $trailMaxLen');
                lines.push('Theorical Max Trail Lenght : $trailCalcMaxLen');
                lines.push('Trail pool : $poolSize');
                lines.push('Num Indices : $trailRealIndicies');
                lines.push('Num Allocated Indices : $trailAllocIndicies');*/
            }
            statusText.text = lines.join("\n");
        }

        var cam = scene.s3d.camera;
        if( light != null ) {
            var angle = Math.atan2(cam.target.y - cam.pos.y, cam.target.x - cam.pos.x);
            light.setDirection(new h3d.Vector(
                Math.cos(angle) * lightDirection.x - Math.sin(angle) * lightDirection.y,
                Math.sin(angle) * lightDirection.x + Math.cos(angle) * lightDirection.y,
                lightDirection.z
            ));
        }
        if( autoSync && (currentVersion != undo.currentID || lastSyncChange != properties.lastChange) ) {
            save();
            lastSyncChange = properties.lastChange;
            currentVersion = undo.currentID;
        }
    }

    static function getTrack(element : PrefabElement, propName : String) {
        return Curve.getCurve(element, propName, false);
    }

    static function upperCase(prop: String) {
        if(prop == null) return "";
        return prop.charAt(0).toUpperCase() + prop.substr(1);
    }

    static function isInstanceCurve(curve: Curve) {
        return curve.getParent(hrt.prefab2.fx.Emitter) != null;
    }

    // TODO(ces) : restrore
    static var _ = FileTree.registerExtension(FXEditor, ["fx2"], { icon : "sitemap", createNew : "FX2" });
}


class FX2DEditor extends FXEditor {

    /*override function getDefaultContent() {
        return haxe.io.Bytes.ofString(ide.toJSON(new hrt.prefab2.fx.FX2D().saveData()));
    }*/

    // TODO(ces) : restore
    //static var _2d = FileTree.registerExtension(FX2DEditor, ["fx2d"], { icon : "sitemap", createNew : "FX 2D" });
}


