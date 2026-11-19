import assert from "node:assert/strict";
import {test} from "node:test";
import {
  encryptPrivateStructuredPreview,
  decryptPrivateStructuredPreview
} from "../functions/_shared/structured_archive_crypto.mjs";

const owner="11111111-2222-4333-8444-555555555555";
const other="99999999-2222-4333-8444-555555555555";
const space="88888888-2222-4333-8444-555555555555";
const passphrase="OneSpace owner recovery passphrase 2026";
const tripPreview={
  payload:{
    schema:"onespace.private-trip-structured-preview.v1",
    owner_id:owner,
    source_space_id:space,
    root:{table:"shared_trips",source_id:"55555555-2222-4333-8444-555555555555",
      structured:{title:"Our private weekend",visibility:"private",created_by:owner}},
    children:{
      trip_flight_options:[{source_id:"66666666-2222-4333-8444-555555555555",
        structured:{title:"Flight to visit family",notes:"Window seat"}}],
      trip_items:[],
      trip_messages:[{source_id:"77777777-2222-4333-8444-555555555555",
        structured:{body:"We made beautiful plans"}}]
    },
    child_record_count:2
  },
  media_included:false,documents_included:false,encrypted:false,
  can_restore:false,is_verified_archive:false
};
const taskPreview={
  ...tripPreview,
  payload:{
    schema:"onespace.private-task-checklist-preview.v1",
    owner_id:owner,source_space_id:space,
    root:{table:"tasks",source_id:"aaaaaaaa-2222-4333-8444-555555555555",
      structured:{title:"Family plans",visibility:"private",created_by:owner}},
    children:{
      task_checklist_items:[{source_id:"bbbbbbbb-2222-4333-8444-555555555555",
        structured:{title:"Remember gifts"}}],
      task_checklist_checks:[]
    },child_record_count:1
  }
};
const copy=(value)=>structuredClone(value);

test("QA prototype encrypts and decrypts private trip and checklist previews",async()=>{
  for(const preview of [tripPreview,taskPreview]){
    const sealed=await encryptPrivateStructuredPreview(preview,passphrase);
    assert.equal(sealed.cipher,"AES-256-GCM");
    assert.equal(sealed.kdf,"PBKDF2-HMAC-SHA256");
    assert.equal(sealed.iterations,600000);
    assert.equal(sealed.kind,"private");
    assert.equal(sealed.can_restore,false);
    assert.equal(sealed.is_verified_archive,false);
    assert.ok(!JSON.stringify(sealed).includes("Our private weekend"));
    assert.ok(!JSON.stringify(sealed).includes("Remember gifts"));
    const opened=await decryptPrivateStructuredPreview(sealed,passphrase,owner);
    assert.deepEqual(opened.payload,preview.payload);
    assert.equal(opened.can_restore,false);
    assert.equal(opened.is_verified_archive,false);
  }
});
test("different salt and IV produce independent ciphertexts",async()=>{
  const a=await encryptPrivateStructuredPreview(tripPreview,passphrase);
  const b=await encryptPrivateStructuredPreview(tripPreview,passphrase);
  assert.notEqual(a.salt_b64,b.salt_b64);
  assert.notEqual(a.iv_b64,b.iv_b64);
  assert.notEqual(a.ciphertext_b64,b.ciphertext_b64);
});
test("wrong passphrase, tampered ciphertext and altered account identity fail",async()=>{
  const e=await encryptPrivateStructuredPreview(tripPreview,passphrase);
  await assert.rejects(
    decryptPrivateStructuredPreview(e,"The wrong password is long enough",owner),
    /decryption or authentication failed/);
  const bad=copy(e);
  const chars=bad.ciphertext_b64.split("");
  chars[12]=chars[12]==="A"?"B":"A";
  bad.ciphertext_b64=chars.join("");
  await assert.rejects(
    decryptPrivateStructuredPreview(bad,passphrase,owner),
    /decryption or authentication failed/);
  await assert.rejects(decryptPrivateStructuredPreview(e,passphrase,other),
    /Unsupported or invalid/);
  const redirected=copy(e);redirected.owner_id=other;
  await assert.rejects(
    decryptPrivateStructuredPreview(redirected,passphrase,other),
    /decryption or authentication failed/);
});
test("KDF downgrade and recovery metadata tampering fail closed",async()=>{
  const e=await encryptPrivateStructuredPreview(taskPreview,passphrase);
  for(const [key,value] of [
    ["iterations",10],["kdf","PBKDF2-SHA1"],["cipher","AES-CBC"],
    ["media_included",true],["is_verified_archive",true],["can_restore",true],
    ["kind","shared"],["salt_b64","!!"]
  ]){
    const copyEnvelope=copy(e);copyEnvelope[key]=value;
    await assert.rejects(
      decryptPrivateStructuredPreview(copyEnvelope,passphrase,owner),
      /Unsupported or invalid/);
  }
});
test("insufficient passphrases and foreign-owner previews rejected",async()=>{
  await assert.rejects(encryptPrivateStructuredPreview(tripPreview,"short"),
    /passphrase must contain/);
  const foreign=copy(tripPreview);
  foreign.payload.owner_id="not-a-user-id";
  await assert.rejects(encryptPrivateStructuredPreview(foreign,passphrase),
    /Unsupported or invalid/);
  await assert.rejects(
    decryptPrivateStructuredPreview({},passphrase,owner),
    /Unsupported or invalid/);
});
test("media pointers, storage paths, embedded binary and shared-scope restore are rejected",async()=>{
  for(const key of ["photo_1_id","file_path","file_name","voice_path","document_id"]){
    const v=copy(taskPreview);
    v.payload.root.structured[key]="file-secret";
    await assert.rejects(encryptPrivateStructuredPreview(v,passphrase),
      /Unsupported or invalid/);
  }
  const withMedia=copy(tripPreview);
  withMedia.payload.children.trip_messages[0].structured.body=
    "private https://qa.invalid/storage/v1/object/public/photo.jpg";
  await assert.rejects(encryptPrivateStructuredPreview(withMedia,passphrase),
    /Unsupported or invalid/);
  const shared=copy(taskPreview);shared.payload.schema="onespace.shared-history.v1";
  await assert.rejects(encryptPrivateStructuredPreview(shared,passphrase),
    /Unsupported or invalid/);
  const falselyVerified=copy(taskPreview);falselyVerified.is_verified_archive=true;
  await assert.rejects(encryptPrivateStructuredPreview(falselyVerified,passphrase),
    /Unsupported or invalid/);
});
