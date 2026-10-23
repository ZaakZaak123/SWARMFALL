"""Upload an optimized FBX once, with resumable operation and no embedded secrets."""
import json,os,sys,time,uuid,urllib.request
from pathlib import Path
weapon=sys.argv[1]
variant=sys.argv[2] if len(sys.argv)>2 else 'standard'
assert variant in ('standard','quality')
assert weapon in ('W01','W02')
root=Path(__file__).resolve().parents[1]/'production/weapons/optimized'/weapon
key=os.environ['ROBLOX_OPEN_CLOUD_KEY']
def request(url,data=None,content_type=None):
    headers={'x-api-key':key}
    if content_type:headers['Content-Type']=content_type
    with urllib.request.urlopen(urllib.request.Request(url,data=data,headers=headers),timeout=90) as response:return json.load(response)
operation=root/('upload_operation.json' if variant=='standard' else 'upload_'+variant+'_operation.json')
if operation.exists():result=json.loads(operation.read_text())
else:
    boundary=uuid.uuid4().hex
    meta={'assetType':'Model','displayName':'SWARMFALL '+weapon+' optimized','description':'Original weapon, optimized geometry with preserved animation groups','creationContext':{'creator':{'userId':os.environ['ROBLOX_USER_ID']}}}
    body=(f'--{boundary}\r\nContent-Disposition: form-data; name="request"\r\n\r\n'+json.dumps(meta)+f'\r\n--{boundary}\r\nContent-Disposition: form-data; name="fileContent"; filename="{weapon}_optimized.fbx"\r\nContent-Type: model/fbx\r\n\r\n').encode()+(root/(weapon+'_optimized.fbx')).read_bytes()+f'\r\n--{boundary}--\r\n'.encode()
    result=request('https://apis.roblox.com/assets/v1/assets',body,'multipart/form-data; boundary='+boundary)
    operation.write_text(json.dumps(result,indent=2))
for i in range(30):
    result=request('https://apis.roblox.com/assets/v1/'+result['path'])
    if result.get('done'):
        (root/('upload_result.json' if variant=='standard' else 'upload_'+variant+'_result.json')).write_text(json.dumps(result,indent=2));print(json.dumps(result));break
    time.sleep(3)
else:print('PENDING',result['path'])
