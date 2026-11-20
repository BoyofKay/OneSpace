// QA account deletion worker (founder rules, ADR 2026-11-20).
//
// Runs every hour from pg_cron with the shared worker secret.
//  1. For every account whose seven-day grace has ended (and was not
//     cancelled): delete its content (private + current couple's shared,
//     partner unpaired) in one database transaction, then delete the sign-in
//     identity through the Auth admin API, then mark the request completed.
//     A failure is recorded and retried next hour; nothing is reported as
//     deleted unless it was.
//  2. Remove file bytes whose record no longer exists (already unreadable).
const env = (key: string) => (Deno.env.get(key) ?? "").trim();
const json = (status: number, data: Record<string, unknown>) =>
  new Response(JSON.stringify(data), {
    status,
    headers: {
      "content-type": "application/json",
      "cache-control": "no-store",
      "x-content-type-options": "nosniff",
    },
  });

Deno.serve(async (req: Request) => {
  if (req.method !== "POST") return json(405, { error: "POST required" });
  const secret = env("ONESPACE_PUSH_CRON_SECRET");
  if (!secret || req.headers.get("x-onespace-push-secret") !== secret) {
    return json(401, { error: "Unauthorized" });
  }
  const base = env("SUPABASE_URL");
  const service = env("SUPABASE_SERVICE_ROLE_KEY");
  if (!base || !service || new URL(base).hostname !== "ugwrpeduzyzrujkizqfo.supabase.co") {
    return json(503, { error: "QA-only account deletion service unavailable" });
  }
  const headers = {
    apikey: service,
    Authorization: "Bearer " + service,
    "content-type": "application/json",
  };
  const rpc = async (name: string, body: Record<string, unknown> = {}) => {
    const r = await fetch(`${base}/rest/v1/rpc/${name}`, {
      method: "POST",
      headers,
      body: JSON.stringify(body),
    });
    if (!r.ok) throw new Error(`${name} failed (${r.status}): ${(await r.text()).slice(0, 300)}`);
    const text = await r.text();
    return text ? JSON.parse(text) : null;
  };

  // 1. Accounts past their grace period.
  let due: string[] = [];
  try {
    const list = await rpc("purge_due_accounts_list");
    due = Array.isArray(list) ? list.map(String) : [];
  } catch (e) {
    console.error("Deletion schedule unavailable", String(e));
    return json(503, { error: "Unable to read account deletion schedule" });
  }

  let deleted = 0;
  const failed: string[] = [];
  for (const user of due) {
    try {
      const result = await rpc("purge_account_content", { p_user: user });
      if (result?.status !== "content_deleted") continue; // cancelled meanwhile
      const auth = await fetch(`${base}/auth/v1/admin/users/${user}`, {
        method: "DELETE",
        headers,
      });
      if (!auth.ok && auth.status !== 404) {
        throw new Error(`auth delete failed (${auth.status}): ${(await auth.text()).slice(0, 300)}`);
      }
      await rpc("mark_account_deleted", { p_user: user, p_error: null }).catch(() => {});
      deleted++;
    } catch (e) {
      failed.push(user);
      console.error("Account deletion failed; will retry", user, String(e));
      await rpc("mark_account_deleted", { p_user: user, p_error: String(e).slice(0, 500) })
        .catch(() => {});
    }
  }

  // 2. File bytes without a record.
  let filesRemoved = 0;
  try {
    const orphans = await rpc("orphan_storage_objects", { p_limit: 300 });
    const byBucket = new Map<string, string[]>();
    for (const o of Array.isArray(orphans) ? orphans : []) {
      const list = byBucket.get(o.bucket_id) ?? [];
      list.push(o.name);
      byBucket.set(o.bucket_id, list);
    }
    for (const [bucket, names] of byBucket) {
      const r = await fetch(`${base}/storage/v1/object/${bucket}`, {
        method: "DELETE",
        headers,
        body: JSON.stringify({ prefixes: names }),
      });
      if (r.ok) filesRemoved += names.length;
      else console.error("File cleanup failed", bucket, r.status, (await r.text()).slice(0, 200));
    }
  } catch (e) {
    console.error("File cleanup unavailable", String(e));
  }

  return json(failed.length ? 207 : 200, {
    due_accounts: due.length,
    accounts_deleted: deleted,
    accounts_failed: failed.length,
    files_removed: filesRemoved,
  });
});
