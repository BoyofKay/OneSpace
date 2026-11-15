// R59: deletes accounts whose 7-day grace period has passed (D47).
// Shared items stay for the partner; private items, personal settings and
// their files are removed, then the sign-in is soft-deleted (email/phone
// anonymised, row kept so shared items keep a valid author).
// Called daily by pg_cron with the same worker secret as push delivery.
const env = (key: string) => Deno.env.get(key)?.trim() ?? "";
const json = (status: number, body: unknown) =>
  new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } });

Deno.serve(async (req: Request) => {
  const secret = env("ONESPACE_PUSH_CRON_SECRET");
  if (!secret) return json(503, { error: "Worker not configured" });
  if (req.headers.get("x-onespace-push-secret") !== secret) return json(401, { error: "Unauthorized" });
  const url = env("SUPABASE_URL"), key = env("SUPABASE_SERVICE_ROLE_KEY");
  const headers = { apikey: key, Authorization: `Bearer ${key}`, "Content-Type": "application/json" };
  const rpc = async (name: string, body: unknown) => {
    const r = await fetch(`${url}/rest/v1/rpc/${name}`, { method: "POST", headers, body: JSON.stringify(body) });
    if (!r.ok) throw new Error(`${name}: ${r.status} ${(await r.text()).slice(0, 300)}`);
    const text = await r.text();
    return text ? JSON.parse(text) : null;
  };

  const due: string[] = (await rpc("purge_due_accounts_list", {})) ?? [];
  const results: Record<string, string> = {};
  for (const id of due) {
    try {
      const files: { bucket: string; path: string }[] = (await rpc("purge_account_data_service", { target: id })) ?? [];
      const byBucket = new Map<string, string[]>();
      for (const f of files) {
        if (!f?.bucket || !f?.path) continue;
        byBucket.set(f.bucket, [...(byBucket.get(f.bucket) ?? []), f.path]);
      }
      for (const [bucket, paths] of byBucket) {
        for (let i = 0; i < paths.length; i += 100) {
          const r = await fetch(`${url}/storage/v1/object/${bucket}`, {
            method: "DELETE", headers, body: JSON.stringify({ prefixes: paths.slice(i, i + 100) }),
          });
          if (!r.ok) throw new Error(`storage ${bucket}: ${r.status}`);
        }
      }
      const del = await fetch(`${url}/auth/v1/admin/users/${id}`, {
        method: "DELETE", headers, body: JSON.stringify({ should_soft_delete: true }),
      });
      if (!del.ok && del.status !== 404) throw new Error(`auth delete: ${del.status} ${(await del.text()).slice(0, 200)}`);
      await rpc("finish_account_purge", { target: id, failure: null });
      results[id] = "deleted";
    } catch (e) {
      const message = e instanceof Error ? e.message : String(e);
      results[id] = "failed";
      try { await rpc("finish_account_purge", { target: id, failure: message.slice(0, 1900) }); } catch { /* logged below */ }
      console.error("purge failed", id, message);
    }
  }
  return json(200, { processed: due.length, results });
});
