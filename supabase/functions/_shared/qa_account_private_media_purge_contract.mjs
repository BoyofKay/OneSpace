// Pure QA service-worker guard. NEVER include relationship/shared buckets.
const UUID=/^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const BUCKETS=Object.freeze({
 "onespace-private-note-images":new Set(["jpg","jpeg","png","webp"]),
 "onespace-private-memory-photos":new Set(["jpg","jpeg","png","webp"]),
 "onespace-private-trip-documents":new Set(["pdf","jpg","jpeg","png","webp"]),
 "onespace-private-share-in":new Set(["pdf","jpg","jpeg","png","webp","heic"]),
 "onespace-private-activity-media":new Set(["jpg","jpeg","png","webp"]),
 "onespace-private-activity-voice":new Set(["m4a"]),
});
export function validateAccountPurgeJob(input){
 if(!input||typeof input!=="object")return null;
 const {owner_id,bucket_id,object_path,lease_id}=input;
 if(typeof owner_id!=="string"||!UUID.test(owner_id)||
    typeof lease_id!=="string"||!UUID.test(lease_id)||
    typeof bucket_id!=="string"||!Object.hasOwn(BUCKETS,bucket_id)||
    typeof object_path!=="string"||object_path.length>400||
    object_path.startsWith("/")||object_path.includes("..")||
    object_path.includes("\\"))return null;
 const parts=object_path.split("/");
 const inbox=bucket_id==="onespace-private-share-in";
 if(parts.length!==(inbox?2:3))return null;
 const pathOwner=inbox?parts[0]:parts[1];
 if(pathOwner!==owner_id)return null;
 if(!inbox&&!UUID.test(parts[0]))return null;
 const file=parts.at(-1);
 const dot=file.lastIndexOf(".");
 if(dot<=0||!UUID.test(file.slice(0,dot))||
    !BUCKETS[bucket_id].has(file.slice(dot+1)))return null;
 return {owner_id,bucket_id,object_path,lease_id};
}
