import {createAccountWebHandler,type AccountWebComposition} from './web/account';
import {fixtureLifecycleFetch,type LifecycleComposition} from './billing/handler';
import { fixtureActivationFetch } from './activations';
import { fixtureBillingFetch } from './billing/webhook';
import type { BillingComposition } from './billing/config';
import { fixtureLicensingFetch } from './entitlements';
import { fixtureAuthFetch } from './auth';
import { assertFixtureEnvironment, type FixtureEnvironment } from "./environment";

// Marker checks separate fixtures from wrong configuration; they authenticate nobody.
// These toy D1 routes are not licensing APIs and must never be deployed.
function result(status: number, outcome: string): Response {
  return Response.json({ fixture: "PAT-2639-local-only", outcome }, {
    status,
    headers: { "Cache-Control": "no-store" },
  });
}
export async function fixtureApplicationFetch(request: Request, env: FixtureEnvironment, billing?: BillingComposition, lifecycle?: LifecycleComposition, web?: AccountWebComposition): Promise<Response> {
    try { assertFixtureEnvironment(env); }
    catch { return result(503, "refused"); }
    const path = new URL(request.url).pathname;
    if (path === "/__fixture/web/account" || path.startsWith("/__fixture/web/account/")) return createAccountWebHandler(web)(request);
    if (path.startsWith("/__fixture/lifecycle/")) return fixtureLifecycleFetch(request, env, lifecycle);
    if (path.startsWith("/__fixture/activations/")) return fixtureActivationFetch(request, env);
    if (path.startsWith("/__fixture/billing/")) return fixtureBillingFetch(request, env, billing);
    if (path.startsWith("/__fixture/licensing/")) return fixtureLicensingFetch(request, env);
    if (path.startsWith("/__fixture/accounts/")) return fixtureAuthFetch(request, env);
    if (path !== "/__fixture/rollback" && path !== "/__fixture/commit") return result(404, "refused");
    if (request.method !== "POST") return result(405, "refused");
    const db = env.FIXTURE_DB;
    if (!db) return result(503, "refused");
    if (path === "/__fixture/rollback") {
      try {
        // The last statement violates the seed's primary key after two writes.
        // D1.batch must atomically undo both earlier statements.
        await db.batch([
          db.prepare("UPDATE t0_guard SET revision = revision + 1 WHERE id = 1"),
          db.prepare("INSERT INTO t0_events VALUES ('rollback', 'must never persist')"),
          db.prepare("INSERT INTO t0_events VALUES ('seed', 'deliberate duplicate')"),
        ]);
      } catch (error) {
        // Exact local workerd shape observed against the isolated seed fixture.
        // Other failures do not establish the intended constraint rollback.
        const constraint = "UNIQUE constraint failed: t0_events.id: SQLITE_CONSTRAINT (extended: SQLITE_CONSTRAINT_PRIMARYKEY)";
        if (error instanceof Error && error.message === `D1_ERROR: ${constraint}` &&
            error.cause instanceof Error && error.cause.message === constraint) {
          return result(409, "rolled-back");
        }
        return result(503, "refused");
      }
      return result(500, "unexpected-commit");
    }
    try {
      await db.batch([
        db.prepare("UPDATE t0_guard SET revision = revision + 1 WHERE id = 1"),
        db.prepare("INSERT INTO t0_events VALUES ('committed', 'positive control')"),
      ]);
      return result(200, "committed");
    } catch { return result(503, "refused"); }
}
export default { fetch: (request:Request,env:FixtureEnvironment) => fixtureApplicationFetch(request,env) };
