"""Upload this FBX once to the owner's Roblox inventory; resume saved operation."""
import json, os, time, urllib.request, uuid
from pathlib import Path
ROOT=Path(__file__).resolve().parent
key=os.environ['ROBLOX_OPEN_CLOUD_KEY']
operation=ROOT/'upload_operation.json'
def call(url, data=None, content_type=None):
    headers={'x-api-key':key}
    if content_type:headers['Content-Type']=content_type
    req=urllib.request.Request(url,data=data,headers=headers)
    with urllib.request.urlopen(req,timeout=90) as r:return json.load(r)
if not operation.exists():
    boundary=uuid.uuid4().hex
    metadata={'assetType':'Model','displayName':'SWARMFALL W02 Vulcan','description':'Original Blender pump shotgun for SWARMFALL','creationContext':{'creator':{'userId':os.environ['ROBLOX_USER_ID']}}}
    body=(f'--{boundary}\r\nContent-Disposition: form-data; name="request"\r\n\r\n'+json.dumps(metadata)+f'\r\n--{boundary}\r\nContent-Disposition: form-data; name="fileContent"; filename="W02_vulcan.fbx"\r\nContent-Type: model/fbx\r\n\r\n').encode()+(ROOT/'W02_vulcan.fbx').read_bytes()+f'\r\n--{boundary}--\r\n'.encode()
    result=call('https://apis.roblox.com/assets/v1/assets',body,'multipart/form-data; boundary='+boundary)
    operation.write_text(json.dumps(result,indent=2))
else:result=json.loads(operation.read_text())
path=result['path']
for i in range(30):
    state=call('https://apis.roblox.com/assets/v1/'+path)
    if state.get('done'):
        (ROOT/'upload_result.json').write_text(json.dumps(state,indent=2));print(json.dumps(state));break
    time.sleep(3)
else:print('Upload operation pending:',path)
