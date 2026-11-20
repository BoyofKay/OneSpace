import test from "node:test";
import assert from "node:assert/strict";
import {validateAccountPurgeJob} from "./qa_account_private_media_purge_contract.mjs";
const owner="a1111111-1111-4111-8111-111111111111";
const other="b2222222-2222-4222-8222-222222222222";
const root="c3333333-3333-4333-8333-333333333333";
const file="d4444444-4444-4444-8444-444444444444";
const lease="e5555555-5555-4555-8555-555555555555";
const sample=(bucket_id,ext,inbox=false)=>({
 owner_id:owner,lease_id:lease,bucket_id,
 object_path:inbox?`${owner}/${file}.${ext}`:`${root}/${owner}/${file}.${ext}`,
});
test("Each account-private file type passes only its own bucket/path contract",()=>{
 for(const [bucket,ext,inbox] of [
  ["onespace-private-note-images","jpg",false],
  ["onespace-private-memory-photos","webp",false],
  ["onespace-private-trip-documents","pdf",false],
  ["onespace-private-share-in","heic",true],
  ["onespace-private-activity-media","png",false],
  ["onespace-private-activity-voice","m4a",false],
  ["onespace-support","jpg",true],
 ]){
  const original=bucket==="onespace-support"
    ? {...sample(bucket,ext,inbox),object_path:`${owner}/1763638800000.jpg`}
    :sample(bucket,ext,inbox);
  assert.deepEqual(validateAccountPurgeJob(original),original);
 }
});
test("Shared, support, archive and unknown buckets cannot be physically deleted",()=>{
 for(const bucket of [
  "onespace-activity-media","onespace-activity-voice",
  "onespace-note-images","onespace-memory-photos",
  "onespace-trip-documents","onespace-share-in",
  "onespace-archives","onespace-support","other",
 ]){
  assert.equal(validateAccountPurgeJob(sample(bucket,"jpg")),null);
 }
});
test("Never permit a forged different account, path traversal or extension",()=>{
 const okay=sample("onespace-private-activity-media","jpg");
 for(const bad of [
  {...okay,owner_id:other},
  {...okay,object_path:`${root}/${other}/${file}.jpg`},
  {...okay,object_path:`${root}/${owner}/../${file}.jpg`},
  {...okay,object_path:`${root}/${owner}/${file}.pdf`},
  {...okay,object_path:`${root}/${owner}/${file}.JPG`},
  {...okay,object_path:`${owner}/${file}.jpg`},
  {...okay,object_path:`/${root}/${owner}/${file}.jpg`},
  {...okay,object_path:`${root}\\${owner}\\${file}.jpg`},
  {...okay,object_path:`${root}/${owner}/${file}.jpg/extra`},
  {...okay,object_path:"x".repeat(401)},
  {...okay,lease_id:other.slice(1)},
  null,{}, 
 ]) assert.equal(validateAccountPurgeJob(bad),null);
});
test("Private Share-in accepts account-root path only",()=>{
 const ok=sample("onespace-private-share-in","pdf",true);
 assert.deepEqual(validateAccountPurgeJob(ok),ok);
 assert.equal(validateAccountPurgeJob({...ok,object_path:`${root}/${owner}/${file}.pdf`}),null);
 assert.equal(validateAccountPurgeJob({...ok,object_path:`${other}/${file}.pdf`}),null);
});

test("Support screenshot cleanup only allows actual owner and 13-digit timestamp",()=>{
 const ok={...sample("onespace-support","png",true),
  object_path:`${owner}/1763638800000.png`};
 assert.deepEqual(validateAccountPurgeJob(ok),ok);
 for(const path of [
  `${other}/1763638800000.png`,
  `${owner}/1763638800000.pdf`,
  `${owner}/image.png`,
  `${owner}/17636388000000.jpg`,
  `${root}/${owner}/1763638800000.jpg`,
 ]) assert.equal(validateAccountPurgeJob({...ok,object_path:path}),null);
});
