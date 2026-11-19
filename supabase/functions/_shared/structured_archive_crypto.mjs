// OneSpace QA-only portable encryption primitive for approved structured
// private-preview payloads. No uploaded media, no shared-history restore.
// This utility does NOT issue/verify a trusted archive, persist anything,
// or authorize account/space deletion. Restoration still requires a trusted
// origin proof, authenticated owner and relational integrity validation.
const FORMAT="onespace.structured-encryption-preview.v1";
const KDF_ITERATIONS=600_000;
const MAX_PLAINTEXT=2*1024*1024;
const MAX_CIPHERTEXT=MAX_PLAINTEXT+32;
const OWNER_RE=/^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const ALLOWED_SCHEMAS=new Set([
  "onespace.private-trip-structured-preview.v1",
  "onespace.private-task-checklist-preview.v1"
]);
const encoder=new TextEncoder();
const decoder=new TextDecoder("utf-8",{fatal:true});
const fail=()=>{throw new Error("Unsupported or invalid structured archive preview");};
function base64(bytes){
  let text="";
  for(let i=0;i<bytes.length;i+=32768){
    text+=String.fromCharCode(...bytes.subarray(i,i+32768));
  }
  return btoa(text);
}
function fromBase64(value,max){
  if(typeof value!=="string"||value.length>Math.ceil(max/3)*4+4
     ||value.length%4!==0||!/^[A-Za-z0-9+/]+={0,2}$/.test(value))fail();
  let binary;
  try{binary=atob(value)}catch{fail()}
  if(binary.length>max)fail();
  return Uint8Array.from(binary,x=>x.charCodeAt(0));
}
function validOwner(userId){
  return typeof userId==="string"&&OWNER_RE.test(userId);
}
function assertStructuredOnly(node,depth=0){
  if(depth>32)fail();
  if(Array.isArray(node)){
    if(node.length>2000)fail();
    for(const value of node)assertStructuredOnly(value,depth+1);
    return;
  }
  if(node!==null&&typeof node==="object"){
    for(const [key,value] of Object.entries(node)){
      // Fail on storage identifiers and media data even if a future SQL
      // sanitizer misses a newly introduced field.
      if(/^(photo_[0-9]+_id|image_[0-9]+_id)$/i.test(key)
       ||/^(object_path|file_path|file_name|file_mime|file_size|voice_path|voice_seconds|photo_id|image_id|media_id|file_id|attachment_id|document_id|thumbnail_path|cover_photo_id|cover_image_id)$/i.test(key)
       ||/^(photos?|images?|files?|documents?|attachments?|audio|video|voice|media|binary|blob|base64|data_uri)$/i.test(key))fail();
      assertStructuredOnly(value,depth+1);
    }
    return;
  }
  if(typeof node==="string"){
    if(/(?:\/storage\/v1\/object\/|\bdata:(?:image|audio|video|application\/(?:pdf|octet-stream))|\bblob:|\bfile:|content:\/\/)/i.test(node))fail();
  }else if(typeof node==="number"){
    if(!Number.isFinite(node))fail();
  }else if(node!==null&&typeof node!=="boolean")fail();
}
function checkPayload(preview){
  if(!preview||typeof preview!=="object"||Array.isArray(preview)
   ||preview.media_included!==false||preview.documents_included!==false
   ||preview.encrypted!==false||preview.can_restore!==false
   ||preview.is_verified_archive!==false)fail();
  const payload=preview.payload;
  if(!payload||typeof payload!=="object"||Array.isArray(payload)
    ||!ALLOWED_SCHEMAS.has(payload.schema)
    ||!validOwner(payload.owner_id)||!validOwner(payload.source_space_id))fail();
  assertStructuredOnly(payload);
  return payload;
}
function checkPassword(passphrase){
  if(typeof passphrase!=="string"||passphrase.length<16
    ||passphrase.length>256)throw new Error("Archive passphrase must contain 16–256 characters");
}
function aad(ownerId){
  return encoder.encode(FORMAT+"|private|"+ownerId.toLowerCase());
}
async function derive(passphrase,salt){
  const secret=await crypto.subtle.importKey("raw",encoder.encode(passphrase),
    "PBKDF2",false,["deriveKey"]);
  return crypto.subtle.deriveKey(
    {name:"PBKDF2",salt,iterations:KDF_ITERATIONS,hash:"SHA-256"},
    secret,{name:"AES-GCM",length:256},false,["encrypt","decrypt"]);
}
export async function encryptPrivateStructuredPreview(preview,passphrase){
  checkPassword(passphrase);
  const payload=checkPayload(preview);
  const bytes=encoder.encode(JSON.stringify(payload));
  if(bytes.byteLength>MAX_PLAINTEXT)fail();
  const salt=crypto.getRandomValues(new Uint8Array(16));
  const iv=crypto.getRandomValues(new Uint8Array(12));
  const key=await derive(passphrase,salt);
  const ciphertext=new Uint8Array(await crypto.subtle.encrypt({
    name:"AES-GCM",iv,additionalData:aad(payload.owner_id),tagLength:128
  },key,bytes));
  return {
    format:FORMAT,
    kind:"private",
    owner_id:payload.owner_id.toLowerCase(),
    media_included:false,
    documents_included:false,
    kdf:"PBKDF2-HMAC-SHA256",
    iterations:KDF_ITERATIONS,
    cipher:"AES-256-GCM",
    salt_b64:base64(salt),
    iv_b64:base64(iv),
    ciphertext_b64:base64(ciphertext),
    is_verified_archive:false,
    can_restore:false
  };
}
export async function decryptPrivateStructuredPreview(envelope,passphrase,expectedOwnerId){
  checkPassword(passphrase);
  if(!validOwner(expectedOwnerId)||!envelope||typeof envelope!=="object"
   ||Array.isArray(envelope)||envelope.format!==FORMAT
   ||envelope.kind!=="private"
   ||envelope.owner_id?.toLowerCase()!==expectedOwnerId.toLowerCase()
   ||envelope.kdf!=="PBKDF2-HMAC-SHA256"||envelope.iterations!==KDF_ITERATIONS
   ||envelope.cipher!=="AES-256-GCM"
   ||envelope.media_included!==false||envelope.documents_included!==false
   ||envelope.is_verified_archive!==false||envelope.can_restore!==false)fail();
  const salt=fromBase64(envelope.salt_b64,16);
  const iv=fromBase64(envelope.iv_b64,12);
  const data=fromBase64(envelope.ciphertext_b64,MAX_CIPHERTEXT);
  if(salt.length!==16||iv.length!==12||data.length<17)fail();
  const key=await derive(passphrase,salt);
  let plaintext;
  try{
    plaintext=await crypto.subtle.decrypt({
      name:"AES-GCM",iv,additionalData:aad(expectedOwnerId),tagLength:128
    },key,data);
  }catch{throw new Error("Archive decryption or authentication failed")}
  let payload;
  try{payload=JSON.parse(decoder.decode(plaintext))}
  catch{fail()}
  const checked=checkPayload({
    payload,media_included:false,documents_included:false,
    encrypted:false,can_restore:false,is_verified_archive:false
  });
  if(checked.owner_id.toLowerCase()!==expectedOwnerId.toLowerCase())fail();
  // Decoding the plaintext succeeds but does not establish server origin,
  // user authorization, original DB ownership or restore eligibility.
  return {payload:checked,is_verified_archive:false,can_restore:false};
}
