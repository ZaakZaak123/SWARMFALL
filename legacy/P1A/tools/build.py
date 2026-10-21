"""Deterministic dependency-free Roblox XML place builder. Python 3.10+."""
from pathlib import Path
import hashlib
import json
import re
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "build"
counter = 0

def prop(item, kind, name, value):
    props = item.find("Properties")
    p = ET.SubElement(props, kind, name=name)
    if kind == "Vector3":
        for k, v in zip(("X", "Y", "Z"), value): ET.SubElement(p, k).text = str(v)
    elif kind == "Color3":
        for k, v in zip(("R", "G", "B"), value): ET.SubElement(p, k).text = str(v / 255)
    elif kind == "CoordinateFrame":
        for k, v in zip(("X", "Y", "Z"), value): ET.SubElement(p, k).text = str(v)
        for row in range(3):
            for col in range(3): ET.SubElement(p, f"R{row}{col}").text = str(int(row == col))
    elif kind == "Content": ET.SubElement(p, "url").text = value
    else: p.text = str(value).lower() if isinstance(value, bool) else str(value)
    return p

def item(parent, cls, name):
    global counter
    counter += 1
    e = ET.SubElement(parent, "Item", {"class": cls, "referent": f"RBX{counter}"})
    ET.SubElement(e, "Properties")
    prop(e, "string", "Name", name)
    return e

def part(parent, name, pos, size, color, material=816, solid=True):
    e = item(parent, "Part", name)
    prop(e, "bool", "Anchored", True)
    prop(e, "bool", "CanCollide", solid)
    prop(e, "bool", "CanTouch", False)
    prop(e, "bool", "CanQuery", solid)
    prop(e, "Vector3", "size", size)
    prop(e, "CoordinateFrame", "CFrame", pos)
    r,g,b = color
    prop(e, "Color3uint8", "Color3uint8", (255 << 24) | (r << 16) | (g << 8) | b)
    prop(e, "token", "Material", material)
    prop(e, "token", "TopSurface", 0)
    prop(e, "token", "BottomSurface", 0)
    return e

def layout():
    text = (ROOT / "src/shared/Layout.luau").read_text(encoding="utf-8")
    obstacles = []
    spawns = []
    for name, values in re.findall(r'\{"([A-Za-z0-9]+)",\s*([^}]+)\}', text):
        nums = [float(v.strip()) for v in values.split(",")]
        if len(nums) == 5: obstacles.append([name, *nums])
        elif len(nums) == 2: spawns.append([name, *nums])
        else: raise ValueError(f"Unsupported layout row: {name}")
    assert len(obstacles) == 14 and len(spawns) == 8
    return obstacles, spawns

def arena(workspace):
    level = item(workspace,"Model","Level01")
    geometry = item(level,"Folder","Geometry")
    decor = item(level,"Folder","Decor")
    markers = item(level,"Folder","SpawnMarkers")
    nav = item(level,"Folder","NavigationHints")
    part(geometry,"ArenaFloor",(0,-1,0),(360,2,320),(42,57,66))
    for name,pos,size in [
        ("WestFence",(-180,6,0),(4,12,324)),("EastFence",(180,6,0),(4,12,324)),
        ("NorthFence",(0,6,160),(360,12,4)),("SouthFence",(0,6,-160),(360,12,4))]:
        part(geometry,name,pos,size,(28,43,55),1088)
        part(decor,name+"Light",(pos[0],12.2,pos[2]),(size[0],.35,size[2]),(40,153,158),288,False)
    for name,x,z,w,d,h in layout()[0]:
        color = (71,91,105) if "Refinery" not in name else (119,78,53)
        part(geometry,name,(x,h/2,z),(w,h,d),color,1088)
        part(decor,name+"Stripe",(x,h+.08,z),(w+.1,.15,1),(255,179,68),288,False)
        for side in (-1,1):
            part(decor,name+f"Rib{side}",(x+side*(w/2+.06),h/2,z),(.18,h+.1,d+.1),(31,44,54),1088,False)
    # Broad unobstructed inner and outer loops. Surface detail is non-colliding.
    for span in (44,144):
        for side in (-1,1):
            part(decor,f"LoopX{span}{side}",(0,.035,side*span),(span*2,.05,2),(45,114,119),272,False)
            part(decor,f"LoopZ{span}{side}",(side*span,.035,0),(2,.05,span*2),(45,114,119),272,False)
    for x in range(-160,161,20):
        part(decor,f"FloorGridX{x}",(x,.015,0),(.12,.02,310),(56,73,82),272,False)
    for z in range(-140,141,20):
        part(decor,f"FloorGridZ{z}",(0,.015,z),(350,.02,.12),(56,73,82),272,False)
    for i in range(4):
        width=30-i*6
        part(decor,f"ReactorInset{i}",(0,.08+i*.02,0),(width,.04,width),(25,78+i*18,88+i*20),288 if i==3 else 1088,False)
    for x in (-39,39):
        part(decor,"ConduitCable",(x,.18,82),(1,.25,84),(67,203,199),288,False)
    for z in (-9,9):
        part(decor,"Rail",(100,.2,z),(112,.3,.7),(121,145,150),1088,False)
    for x in range(52,153,8):
        part(decor,"RailSleeper",(x,.08,0),(1,.12,24),(22,33,41),1088,False)
    # Tank top details stay within solid obstacle footprints.
    for x in (-34,34):
        part(decor,"RefineryCap",(x,9.2,-94),(12,.4,12),(219,137,59),1088,False)
        part(decor,"RefineryBeacon",(x,10,-94),(2,1,2),(255,151,47),288,False)
    for x,z in [(-46,65),(55,-45)]:
        for side in (-1,1): part(decor,"OpenGatePost",(x+side*12,4,z),(2,8,2),(190,163,73),1088,False)
    for x,z in [(-84,76),(102,-74),(0,-110)]:
        part(decor,"FutureHiveSite",(x,.08,z),(8,.08,8),(76,48,77),272,False)
    for name,x,z in layout()[1]:
        p=part(markers,name,(x,.12,z),(12,.12,12),(167,64,48),288,False)
        prop(p,"float","Transparency",.30)
        # Spawn chevrons/readable entry pylons.
        for side in (-1,1): part(decor,name+"Beacon",(x+side*9,2,z),(1.4,4,1.4),(248,124,56),288,False)
    for name,x,z in [("Z0",0,-12),("ZN",0,82),("ZE",100,0),("ZS",0,-85),("ZW",-92,0)]:
        p=part(nav,name,(x,1,z),(1,1,1),(255,255,255),272,False)
        prop(p,"float","Transparency",1)
    return level

def sources(parent, folder):
    for path in sorted((ROOT/folder).glob("*.luau")):
        cls = "LocalScript" if ".client." in path.name else "Script" if ".server." in path.name else "ModuleScript"
        name=path.name.replace(".client.luau","").replace(".server.luau","").replace(".luau","")
        e=item(parent,cls,name)
        prop(e,"ProtectedString","Source",path.read_text(encoding="utf-8"))

def build():
    global counter
    counter=0
    OUT.mkdir(exist_ok=True)
    tree=ET.Element("roblox",version="4")
    ET.SubElement(tree,"External").text="null"
    ET.SubElement(tree,"External").text="nil"
    workspace=item(tree,"Workspace","Workspace")
    prop(workspace,"float","Gravity",196.2)
    level=arena(workspace)
    lighting=item(tree,"Lighting","Lighting")
    prop(lighting,"float","ClockTime",14)
    prop(lighting,"float","Brightness",2)
    prop(lighting,"Color3","Ambient",(115,131,148))
    prop(lighting,"Color3","OutdoorAmbient",(139,151,163))
    prop(lighting,"bool","GlobalShadows",True)
    prop(lighting,"token","Technology",2)
    rs=item(tree,"ReplicatedStorage","ReplicatedStorage")
    shared=item(rs,"Folder","Shared")
    sources(shared,"src/shared")
    remotes=item(rs,"Folder","Remotes")
    for name in ("Input","Snapshot","FX"): item(remotes,"RemoteEvent",name)
    server=item(tree,"ServerScriptService","ServerScriptService")
    sources(server,"src/server")
    starter=item(tree,"StarterPlayer","StarterPlayer")
    scripts=item(starter,"StarterPlayerScripts","StarterPlayerScripts")
    sources(scripts,"src/client")
    character=item(starter,"StarterCharacterScripts","StarterCharacterScripts")
    sources(character,"src/startercharacter")
    item(tree,"StarterGui","StarterGui")
    xml=ET.tostring(tree,encoding="utf-8")
    place=OUT/"SWARMFALL_P1A.rbxlx"
    place.write_bytes(xml)
    model=ET.Element("roblox",version="4")
    model.append(level)
    (OUT/"Level01.rbxmx").write_bytes(ET.tostring(model,encoding="utf-8"))
    files={str(p.relative_to(ROOT)).replace("\\","/"):hashlib.sha256(p.read_bytes()).hexdigest()
           for directory in ("src","tools","tests") for p in sorted((ROOT/directory).rglob("*"))
           if p.is_file() and "__pycache__" not in str(p)}
    manifest={"build":"P1A-20261021","place_sha256":hashlib.sha256(xml).hexdigest(),
              "instances":len(tree.findall(".//Item")),"sources":files}
    (OUT/"manifest.json").write_text(json.dumps(manifest,indent=2),encoding="utf-8")
    print(json.dumps({"place":str(place),"sha256":manifest["place_sha256"],"instances":manifest["instances"]}))
    return tree

if __name__=="__main__": build()
