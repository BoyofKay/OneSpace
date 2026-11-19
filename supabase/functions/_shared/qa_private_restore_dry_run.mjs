// QA-only read-only plan for a FUTURE authenticated private restoration.
// Authenticated owner, trusted issued archive provenance, all 69 table families,
// complete canonical cutover and durable transactional inserts DO NOT exist yet.
// An encrypted preview can be decrypted but is NOT trusted evidence of origin.
import {decryptPrivateStructuredPreview} from "./structured_archive_crypto.mjs";

const VALID_UUID=/^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const CONFIG={
  "onespace.private-task-checklist-preview.v1":{
    root:"tasks",
    children:["task_checklist_items","task_checklist_checks"],
    parentField:"task_id"
  },
  "onespace.private-trip-structured-preview.v1":{
    root:"shared_trips",
    children:["trip_flight_options","trip_items","trip_messages"],
    parentField:"trip_id"
  }
};
const MEDIA_KEY=/(?:^|_)(?:photo|photos|image|images|media|audio|video|voice|attachment|attachments|document|documents|binary|blob|thumbnail|file|files)(?:_|$)/i;
const MEDIA_DATA=/(?:\/storage\/v1\/object\/|\bdata:(?:image|audio|video|application\/(?:pdf|octet-stream))|\bblob:|\bfile:|content:\/\/)/i;
const fail=(msg)=>{throw new Error("Unsafe private restore preview: "+msg)};
const isUuid=x=>typeof x==="string"&&VALID_UUID.test(x);
function inspect(value,depth=0){
  if(depth>24)fail("structured data nesting exceeded");
  if(Array.isArray(value)){
    if(value.length>1500)fail("array cap exceeded");
    for(const x of value)inspect(x,depth+1);
  }else if(value!==null&&typeof value==="object"){
    for(const [key,v] of Object.entries(value)){
      if(MEDIA_KEY.test(key)||/^(object_path|base64|data_uri)$/i.test(key))
        fail("uploaded media key");
      inspect(v,depth+1);
    }
  }else if(typeof value==="string"){
    if(MEDIA_DATA.test(value))fail("uploaded media URL/body");
  }else if(value!==null&&(typeof value==="number"&&!Number.isFinite(value)||
      !["number","boolean"].includes(typeof value)))fail("unserializable data");
}
const object=x=>x!==null&&typeof x==="object"&&!Array.isArray(x);
const uuid=x=>{if(!isUuid(x))fail("invalid record identifier");return x.toLowerCase()};
const stripReference=(record,table,name,dropped)=>{
  if(Object.hasOwn(record,name)&&record[name]!==null){
    dropped.push({table,field:name});
  }
  delete record[name];
};
export function planPrivateRestoreDryRun(payload,{ownerId,newSpaceId}){
  if(!object(payload)||!object(payload.root)||!object(payload.children))
    fail("invalid structured package");
  if(!isUuid(ownerId)||!isUuid(newSpaceId))fail("invalid caller or target space");
  const config=CONFIG[payload.schema];
  if(!config||payload.root.table!==config.root)fail("unsupported private family");
  if(uuid(payload.owner_id)!==uuid(ownerId))fail("archive owner differs from caller");
  if(uuid(payload.source_space_id)===uuid(newSpaceId))
    fail("destination must be a distinct relationship boundary");
  if(!isUuid(payload.source_space_id))fail("source space missing");
  const root=payload.root;
  if(!object(root.structured)||uuid(root.source_id)!==uuid(root.structured.id))
    fail("root source identifier mismatch");
  if(uuid(root.structured.created_by)!==uuid(ownerId) ||
      uuid(root.structured.space_id)!==uuid(payload.source_space_id) ||
      root.structured.visibility!=="private")
    fail("root not owned and private in original space");
  const childNames=Object.keys(payload.children).sort();
  if(JSON.stringify(childNames)!==JSON.stringify([...config.children].sort()))
    fail("unexpected or omitted child table");
  if(!Number.isSafeInteger(payload.child_record_count) ||
      payload.child_record_count<0||payload.child_record_count>500)
    fail("invalid child count");
  const encountered=new Set([uuid(root.source_id)]);
  const mappings=[];
  const dropped=[];
  const newRoot=crypto.randomUUID();
  mappings.push({table:config.root,old_id:root.source_id,new_id:newRoot});
  const rootRow=structuredClone(root.structured);
  rootRow.id=newRoot;
  rootRow.space_id=newSpaceId;
  for(const key of config.root==="tasks"
       ?["assigned_to","trip_id","migrated_to_list"]
       :["traveler_id"]){
    stripReference(rootRow,config.root,key,dropped);
  }
  inspect(rootRow);
  const children={};
  const oldItems=new Set();
  const newItems=new Map();
  for(const name of config.children){
    const rows=payload.children[name];
    if(!Array.isArray(rows)||rows.length>500)fail("invalid child table records");
    children[name]=[];
    for(const entry of rows){
      if(!object(entry)||!object(entry.structured))fail("invalid child row");
      const oldId=uuid(entry.source_id);
      if(encountered.has(oldId))fail("duplicate source identifier");
      encountered.add(oldId);
      const data=structuredClone(entry.structured);
      if(uuid(data.id)!==oldId)fail("child source identifier mismatch");
      if(uuid(data[config.parentField])!==uuid(root.source_id))
        fail("child belongs to another parent");
      if(name==="task_checklist_checks"){
        if(uuid(data.user_id)!==uuid(ownerId))
          fail("check completion belongs to another person");
      }else if(uuid(data.created_by)!==uuid(ownerId))
        fail("child contribution belongs to another person");
      if(data.space_id!=null&&uuid(data.space_id)!==uuid(payload.source_space_id))
        fail("child belongs to another space");
      const newId=crypto.randomUUID();
      if(name==="task_checklist_items"){
        oldItems.add(oldId);newItems.set(oldId,newId);
      }
      data.id=newId;
      data[config.parentField]=newRoot;
      if(Object.hasOwn(data,"space_id"))data.space_id=newSpaceId;
      if(name==="task_checklist_items"){
        stripReference(data,name,"legacy_task_id",dropped);
        stripReference(data,name,"legacy_assigned_to",dropped);
      }
      inspect(data);
      mappings.push({table:name,old_id:oldId,new_id:newId});
      children[name].push(data);
    }
  }
  if(mappings.length-1!==payload.child_record_count)
    fail("child record count mismatch");
  if(config.root==="tasks"){
    for(const row of children.task_checklist_checks){
      // Check references still contain old IDs; they must resolve to an
      // item explicitly included in this self-contained package.
      const oldItem=uuid(row.item_id);
      if(!oldItems.has(oldItem))fail("orphan checklist check");
      row.item_id=newItems.get(oldItem);
      inspect(row);
    }
  }
  return {
    format:"onespace.private-restore-dry-run.v1",
    owner_id:ownerId,destination_space_id:newSpaceId,
    original_space_id:payload.source_space_id,
    source_family:config.root,
    is_verified_archive:false,can_write:false,can_restore:false,
    safe_to_separate:false,
    rows:{root:rootRow,children},
    id_mappings:mappings,
    dropped_external_references:dropped,
    warning:"Non-authoritative remap plan; no storage, database writes, trusted archive provenance or partner separation"
  };
}
export async function planPrivateRestoreFromEncryptedPreview(
  envelope,passphrase,ownerId,newSpaceId
){
  const checked=await decryptPrivateStructuredPreview(envelope,passphrase,ownerId);
  if(checked.is_verified_archive!==false||checked.can_restore!==false)
    fail("preview incorrectly marked verified");
  return planPrivateRestoreDryRun(checked.payload,{ownerId,newSpaceId});
}
