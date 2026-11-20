// QA-only, source-only *rehearsal* for owner-private, single-root records
// already included in a separately verified encrypted .osa subset manifest.
// This module neither authenticates origin nor writes or enables restoration.
// The caller MUST perform full .osa decryption and snapshot/lineage checks.
const SOURCE_FIELDS={
 notes:"id space_id created_by title body visibility pinned archived_at created_at updated_at rich_delta",
 goals:"id space_id created_by title description target_date progress status visibility archived_at created_at updated_at",
 daily_checkins:"id space_id created_by checkin_date mood message gratitude visibility created_at updated_at"
};
const FIELDS=Object.fromEntries(Object.entries(SOURCE_FIELDS).map(
 ([key,value])=>[key,new Set(value.split(" "))]));
const UUID=/^[a-f0-9]{8}-[a-f0-9]{4}-[1-8][a-f0-9]{3}-[89ab][a-f0-9]{3}-[a-f0-9]{12}$/i;
const fail=(s)=>{throw new Error("Unsafe QA standalone private root rehearsal: "+s)};
const object=x=>x!==null&&typeof x==="object"&&!Array.isArray(x);
const equals=(a,b)=>typeof a==="string"&&typeof b==="string"&&
 a.toLowerCase()===b.toLowerCase();

// Only text-only Quill operations are eligible. Never move a rich-text
// image/video/file embed, URL, mention ID or arbitrary partner reference.
function validateTextDelta(delta){
 if(delta==null)return;
 if(!Array.isArray(delta)||delta.length>4000)fail("unreviewed rich-text format");
 for(const op of delta){
  if(!object(op)||Object.keys(op).some(k=>k!=="insert"&&k!=="attributes")
    ||typeof op.insert!=="string")fail("rich-text embed or foreign operation");
  if(op.attributes===undefined)continue;
  if(!object(op.attributes))fail("unreviewed text attributes");
  for(const [name,value] of Object.entries(op.attributes)){
   if(["bold","italic","underline","strike","code","blockquote"].includes(name)
     &&typeof value==="boolean")continue;
   if(name==="header"&&Number.isInteger(value)&&value>=1&&value<=6)continue;
   if(name==="indent"&&Number.isInteger(value)&&value>=0&&value<=8)continue;
   if(name==="list"&&["ordered","bullet","checked","unchecked"].includes(value))continue;
   if(name==="align"&&["left","center","right","justify"].includes(value))continue;
   if(name==="size"&&["small","normal","large","huge"].includes(value))continue;
   if(["color","background"].includes(name)&&
      typeof value==="string"&&/^#[0-9a-fA-F]{6}$/.test(value))continue;
   fail("unreviewed rich-text attribute");
  }
 }
}
export function planReviewedPrivateRoot(record,{ownerId,sourceSpaceId,newSpaceId}){
 if(!object(record)||record.kind!=="root"||!Object.hasOwn(FIELDS,record.source_table))
  fail("unsupported root family");
 if(!UUID.test(ownerId)||!UUID.test(sourceSpaceId)||!UUID.test(newSpaceId)
   ||equals(newSpaceId,sourceSpaceId))fail("invalid independent target space");
 let source;
 try{source=JSON.parse(record.snapshot_json)}
 catch{fail("source snapshot is not JSON")}
 if(!object(source)||!UUID.test(record.source_id)||
   !equals(source.id,record.source_id)||!equals(source.created_by,ownerId)||
   !equals(source.space_id,sourceSpaceId)||source.visibility!=="private")
   fail("original private owner, space or record mismatch");
 const allowed=FIELDS[record.source_table];
 for(const key of Object.keys(source)){
  if(!allowed.has(key))fail("unreviewed root column "+key);
 }
 if(record.source_table==="notes")validateTextDelta(source.rich_delta);
 // No other UUID/FK is in the reviewed root field lists. The source .osa
 // verifier has already rejected nested media pointers and uploaded files.
 const restored=structuredClone(source);
 restored.id=crypto.randomUUID();
 restored.space_id=newSpaceId;
 return {
  format:"onespace.qa.private-standalone-root-plan.v1",
  source_family:record.source_table,
  original_space_id:sourceSpaceId,
  destination_space_id:newSpaceId,
  owner_id:ownerId,
  rows:{root:restored,children:{}},
  id_mappings:[{table:record.source_table,old_id:record.source_id,new_id:restored.id}],
  dropped_external_references:[],
  dependent_content_restored:false,
  // Notes can have separate note_references and note_images; those are NOT
  // included in this root-only plan. note_images are policy-excluded media.
  warning:record.source_table==="notes"
    ?"Note text and reviewed inline formatting only. Linked note_references remain outside this partial rehearsal; media is excluded."
    :"Standalone private root rehearsal only; no trusted issuance or database writes.",
  is_verified_archive:false,can_write:false,can_restore:false,
  safe_to_separate:false
 };
}
