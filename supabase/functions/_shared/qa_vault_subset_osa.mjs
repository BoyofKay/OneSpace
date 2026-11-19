// OneSpace QA private-vault subset .osa format.
// Produces ACTUAL AES-256-GCM encrypted bytes, and independently checks
// every original PostgreSQL JSONB snapshot SHA-256 after decryption.
// NO server-issued provenance, 69-table completeness, or restore permission.
const FORMAT="onespace.qa.vault-subset.osa.v1";
const MANIFEST="onespace.qa.private-vault-subset-manifest.v1";
const SOURCE_DIGEST_PREFIX="onespace.qa.private.vault-subset.v1";
const ITERATIONS=600000;
const MAX_RECORDS=5000;
const MAX_SNAPSHOT_BYTES=8*1024*1024;
const MAX_PLAINTEXT=12*1024*1024;
const MAX_ARCHIVE=20*1024*1024;
const UUID=/^[a-f0-9]{8}-[a-f0-9]{4}-[1-8][a-f0-9]{3}-[89ab][a-f0-9]{3}-[a-f0-9]{12}$/i;
const SHA=/^[a-f0-9]{64}$/;
const ROOTS=new Set([
 "activities","daily_checkins","goals","items_to_sort","memories","notes",
 "occasion_plans","places","reminders","saved_contacts","shared_trips",
 "space_counters","space_events","tasks"
]);
const CHILD_PARENTS={
 occasion_budget_items:["occasion_plans","plan_id"],
 occasion_plan_steps:["occasion_plans","plan_id"],
 occasion_proposals:["occasion_plans","plan_id"],
 reminder_recipients:["reminders","reminder_id"],
 task_checklist_items:["tasks","task_id"],
 task_checklist_checks:["tasks","task_id"],
 trip_flight_options:["shared_trips","trip_id"],
 trip_items:["shared_trips","trip_id"],
 trip_messages:["shared_trips","trip_id"]
};
const ENCODER=new TextEncoder();
const DECODER=new TextDecoder("utf-8",{fatal:true});
const fail=(reason)=>{throw new Error("Invalid QA subset archive: "+reason)};
const uuid=x=>typeof x==="string"&&UUID.test(x);
const obj=x=>x!==null&&typeof x==="object"&&!Array.isArray(x);
const hex=bytes=>Array.from(bytes,b=>b.toString(16).padStart(2,"0")).join("");
const digest=async bytes=>hex(new Uint8Array(await crypto.subtle.digest("SHA-256",bytes)));
const bytes=x=>ENCODER.encode(x);
function base64(data){
 let result="";
 for(let i=0;i<data.length;i+=32768)result+=String.fromCharCode(...data.subarray(i,i+32768));
 return btoa(result);
}
function unbase64(value,limit){
 if(typeof value!=="string"||value.length>Math.ceil(limit/3)*4+4
   ||value.length%4!==0||!/^[A-Za-z0-9+/]+={0,2}$/.test(value))fail("invalid base64");
 let raw;
 try{raw=atob(value)}catch{fail("invalid base64")}
 if(raw.length>limit)fail("oversized base64");
 return Uint8Array.from(raw,ch=>ch.charCodeAt(0));
}
function inspectMedia(node,depth=0){
 if(depth>28)fail("excessive nested source data");
 if(Array.isArray(node)){
  if(node.length>2000)fail("oversized nested array");
  node.forEach(x=>inspectMedia(x,depth+1));return;
 }
 if(obj(node)){
  for(const [key,value] of Object.entries(node)){
   if(/(?:^|_)(?:photo|photos|image|images|media|audio|voice|video|attachment|attachments|document|documents|file|files|thumbnail|blob|binary)(?:_|$)/i.test(key)
     ||/^(object_path|base64|data_uri|cover_photo_id)$/i.test(key))fail("media pointer field");
   inspectMedia(value,depth+1);
  }
  return;
 }
 if(typeof node==="string"){
  if(/(?:\/storage\/v1\/object\/|\bdata:(?:image|audio|video|application\/(?:pdf|octet-stream))|\bblob:|\bfile:|content:\/\/)/i.test(node))
    fail("media pointer in written value");
 }else if(node!==null&&typeof node!=="boolean"&&
         !(typeof node==="number"&&Number.isFinite(node)))
   fail("unsupported data value");
}
function passphraseValid(value){
 if(typeof value!=="string"||value.length<16||value.length>256)
   fail("passphrase must contain 16-256 characters");
}
function aad(owner,space,d){
 return bytes(FORMAT+"|"+owner.toLowerCase()+"|"+space.toLowerCase()+"|"+d);
}
async function keyFrom(password,salt){
 const material=await crypto.subtle.importKey("raw",bytes(password),
   "PBKDF2",false,["deriveKey"]);
 return crypto.subtle.deriveKey({
   name:"PBKDF2",salt,iterations:ITERATIONS,hash:"SHA-256"
 },material,{name:"AES-GCM",length:256},false,["encrypt","decrypt"]);
}
function validBase(manifest,owner,space){
 if(!obj(manifest)||manifest.schema!==MANIFEST
  ||!uuid(manifest.owner_id)||!uuid(manifest.source_space_id)
  ||manifest.owner_id.toLowerCase()!==owner.toLowerCase()
  ||manifest.source_space_id.toLowerCase()!==space.toLowerCase()
  ||manifest.root_types_in_scope!==14||manifest.dependent_types_in_scope!==9
  ||manifest.all_69_types_packaged!==false
  ||manifest.source_manifest_scope_complete!==true
  ||manifest.media_included!==false||manifest.documents_included!==false
  ||manifest.archive_issued!==false||manifest.server_signed!==false
  ||manifest.is_verified_archive!==false||manifest.can_restore!==false
  ||manifest.safe_to_archive!==false||manifest.safe_to_separate!==false)
  fail("manifest identity or scope flag");
 if(!Array.isArray(manifest.records)||manifest.records.length>MAX_RECORDS
   ||manifest.record_count!==manifest.records.length
   ||!Number.isSafeInteger(manifest.root_record_count)
   ||!Number.isSafeInteger(manifest.child_record_count)
   ||manifest.root_record_count+manifest.child_record_count!==manifest.record_count
   ||!Number.isSafeInteger(manifest.snapshot_plaintext_bytes)
   ||manifest.snapshot_plaintext_bytes>MAX_SNAPSHOT_BYTES
   ||!SHA.test(manifest.subset_sha256))
  fail("manifest size/count/hash fields");
}
export async function verifyVaultSubsetManifest(manifest,expectedOwner,expectedSpace){
 if(!uuid(expectedOwner)||!uuid(expectedSpace))fail("invalid expected owner/space");
 validBase(manifest,expectedOwner,expectedSpace);
 const seen=new Set(),roots=new Map();
 const lines=[];
 let sum=0,rootCount=0,childCount=0;
 let previous="";
 for(const record of manifest.records){
  if(!obj(record)||!["root","child"].includes(record.kind)
   ||!uuid(record.source_id)||typeof record.source_table!=="string"
   ||!SHA.test(record.snapshot_sha256)
   ||typeof record.snapshot_json!=="string"
   ||!Number.isSafeInteger(record.snapshot_bytes)
   ||record.snapshot_bytes<2||record.snapshot_bytes>524288)
   fail("invalid per-record attributes");
  const key=record.kind+"|"+record.source_table+"|"+record.source_id.toLowerCase();
  if(seen.has(key)||key<=previous)fail("duplicate or out-of-order source record");
  seen.add(key);previous=key;
  if(record.kind==="root"){
   if(!ROOTS.has(record.source_table)
     ||record.parent_table!==null||record.parent_id!==null)
      fail("unapproved root table or root parent");
   rootCount++;
  }else{
   if(!Object.hasOwn(CHILD_PARENTS,record.source_table)
     ||record.parent_table!==CHILD_PARENTS[record.source_table][0]
     ||!uuid(record.parent_id))
     fail("unapproved dependent table or parent");
   childCount++;
  }
  const raw=bytes(record.snapshot_json);
  if(raw.length!==record.snapshot_bytes||raw.length>524288)
    fail("snapshot byte length mismatch");
  if(await digest(raw)!==record.snapshot_sha256)fail("snapshot SHA-256 mismatch");
  let snapshot;
  try{snapshot=JSON.parse(record.snapshot_json)}catch{fail("invalid snapshot JSON")}
  if(!obj(snapshot)||!uuid(snapshot.id)||
     snapshot.id.toLowerCase()!==record.source_id.toLowerCase())
    fail("snapshot identity not source record");
  inspectMedia(snapshot);
  if(record.kind==="root"){
   if(snapshot.created_by?.toLowerCase()!==expectedOwner.toLowerCase()
      ||snapshot.space_id?.toLowerCase()!==expectedSpace.toLowerCase()
      ||snapshot.visibility!=="private")fail("root owner, space or privacy mismatch");
   roots.set(record.source_table+"|"+record.source_id.toLowerCase(),snapshot);
  }else{
   const [table,fk]=CHILD_PARENTS[record.source_table];
   if(snapshot[fk]?.toLowerCase()!==record.parent_id.toLowerCase())
     fail("dependent parent relation changed");
   const writer=record.source_table==="reminder_recipients"?"recipient_id":
     record.source_table==="task_checklist_checks"?"user_id":"created_by";
   if(snapshot[writer]?.toLowerCase()!==expectedOwner.toLowerCase())
     fail("dependent contributor differs from private owner");
   if(snapshot.space_id!=null &&
      snapshot.space_id.toLowerCase()!==expectedSpace.toLowerCase())
      fail("dependent belongs to different space");
   // Preserve relation integrity without importing previous partner links.
   if(record.source_table==="task_checklist_checks"&&!uuid(snapshot.item_id))
     fail("invalid checklist item link");
   if(record.source_table==="occasion_budget_items"&&
       (snapshot.source_activity_id!=null||snapshot.source_component_id!=null))
     fail("external occasion component link requires explicit portable mapping");
  }
  sum+=raw.length;
  lines.push(key+"|"+record.snapshot_sha256);
 }
 if(sum!==manifest.snapshot_plaintext_bytes
    ||rootCount!==manifest.root_record_count
    ||childCount!==manifest.child_record_count)
    fail("aggregate snapshot counts/bytes mismatch");
 for(const record of manifest.records.filter(r=>r.kind==="child")){
  const parentKey=record.parent_table+"|"+record.parent_id.toLowerCase();
  if(!roots.has(parentKey))fail("orphan dependent parent");
  const snapshot=JSON.parse(record.snapshot_json);
  if(record.source_table==="task_checklist_checks"){
   const matching=manifest.records.some(r=>r.kind==="child"
     &&r.source_table==="task_checklist_items"&&
       r.source_id.toLowerCase()===snapshot.item_id.toLowerCase()
     &&r.parent_id.toLowerCase()===record.parent_id.toLowerCase());
   if(!matching)fail("orphan checklist completion item");
  }
 }
 const checksum=await digest(bytes(
   SOURCE_DIGEST_PREFIX+"|"+expectedOwner.toLowerCase()+"|"+
   expectedSpace.toLowerCase()+"|"+lines.join("\n")
 ));
 if(checksum!==manifest.subset_sha256)
   fail("owner/space bound manifest fingerprint mismatch");
 return {root_count:rootCount,child_count:childCount,
   record_count:manifest.records.length,snapshot_bytes:sum,
   subset_sha256:checksum,fully_restorable:false};
}
export async function encryptVaultSubsetFile(manifest,passphrase){
 passphraseValid(passphrase);
 const owner=manifest?.owner_id,space=manifest?.source_space_id;
 if(!uuid(owner)||!uuid(space))fail("invalid owner/space");
 await verifyVaultSubsetManifest(manifest,owner,space);
 const plain=bytes(JSON.stringify(manifest));
 if(plain.length>MAX_PLAINTEXT)fail("manifest exceeds plaintext capacity");
 const salt=crypto.getRandomValues(new Uint8Array(16));
 const nonce=crypto.getRandomValues(new Uint8Array(12));
 const key=await keyFrom(passphrase,salt);
 const encrypted=new Uint8Array(await crypto.subtle.encrypt({
   name:"AES-GCM",iv:nonce,additionalData:aad(owner,space,manifest.subset_sha256),
   tagLength:128
 },key,plain));
 const cipherHash=await digest(encrypted);
 const envelope={
  format:FORMAT,owner_id:owner.toLowerCase(),
  source_space_id:space.toLowerCase(),
  kind:"qa-private-vault-subset",
  cipher:"AES-256-GCM",kdf:"PBKDF2-HMAC-SHA256",
  iterations:ITERATIONS,
  salt_b64:base64(salt),nonce_b64:base64(nonce),
  ciphertext_b64:base64(encrypted),ciphertext_bytes:encrypted.length,
  ciphertext_sha256:cipherHash,subset_sha256:manifest.subset_sha256,
  media_included:false,documents_included:false,
  all_69_types_packaged:false,server_signed:false,
  is_verified_archive:false,can_restore:false,safe_to_separate:false
 };
 const file=bytes(JSON.stringify(envelope));
 if(file.length>MAX_ARCHIVE)fail("encrypted archive exceeds size limit");
 return file;
}
export async function decryptVaultSubsetFile(file,passphrase,ownerId,spaceId){
 passphraseValid(passphrase);
 if(!uuid(ownerId)||!uuid(spaceId))fail("invalid expected owner/space");
 if(!(file instanceof Uint8Array)||file.length>MAX_ARCHIVE||file.length<100)
   fail("invalid encrypted file size");
 let env;
 try{env=JSON.parse(DECODER.decode(file))}catch{fail("invalid encrypted envelope")}
 if(!obj(env)||env.format!==FORMAT||env.kind!=="qa-private-vault-subset"
   ||env.owner_id?.toLowerCase()!==ownerId.toLowerCase()
   ||env.source_space_id?.toLowerCase()!==spaceId.toLowerCase()
   ||env.cipher!=="AES-256-GCM"||env.kdf!=="PBKDF2-HMAC-SHA256"
   ||env.iterations!==ITERATIONS
   ||env.media_included!==false||env.documents_included!==false
   ||env.all_69_types_packaged!==false||env.server_signed!==false
   ||env.is_verified_archive!==false||env.can_restore!==false
   ||env.safe_to_separate!==false||!SHA.test(env.ciphertext_sha256)
   ||!SHA.test(env.subset_sha256)||!Number.isSafeInteger(env.ciphertext_bytes)
   ||env.ciphertext_bytes<17||env.ciphertext_bytes>MAX_PLAINTEXT+16)
    fail("invalid authenticated envelope attributes");
 const salt=unbase64(env.salt_b64,16);
 const nonce=unbase64(env.nonce_b64,12);
 const ciphertext=unbase64(env.ciphertext_b64,MAX_PLAINTEXT+16);
 if(salt.length!==16||nonce.length!==12||
    ciphertext.length!==env.ciphertext_bytes||
    await digest(ciphertext)!==env.ciphertext_sha256)
    fail("encrypted ciphertext SHA-256 or byte count mismatch");
 const key=await keyFrom(passphrase,salt);
 let plain;
 try{
  plain=await crypto.subtle.decrypt({
   name:"AES-GCM",iv:nonce,additionalData:aad(ownerId,spaceId,env.subset_sha256),
   tagLength:128
  },key,ciphertext);
 }catch{fail("wrong passphrase or AES-GCM authentication mismatch")}
 let manifest;
 try{manifest=JSON.parse(DECODER.decode(plain))}catch{fail("decrypted JSON invalid")}
 if(manifest.subset_sha256!==env.subset_sha256)
   fail("encrypted manifest fingerprint differs from envelope");
 const evidence=await verifyVaultSubsetManifest(manifest,ownerId,spaceId);
 return {manifest,evidence,
   verified_ciphertext:true,verified_password_encryption:true,
   verified_record_snapshots:true,verified_source_origin:false,
   full_69_family_archive:false,is_verified_archive:false,
   can_restore:false,safe_to_separate:false};
}
