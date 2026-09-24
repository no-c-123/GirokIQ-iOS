import { createClient, type SupabaseClient } from "jsr:@supabase/supabase-js@2";
import { corsHeaders } from "../_shared/cors.ts";

Deno.serve(async (request) => {
  if (request.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  if (request.method !== "POST") {
    return jsonResponse({ error: "Method not allowed." }, 405);
  }

  const supabaseURL = Deno.env.get("SUPABASE_URL");
  const supabaseAnonKey = Deno.env.get("SUPABASE_ANON_KEY");
  const serviceRoleKey = Deno.env.get("SERVICE_ROLE_KEY") ??
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");

  if (!supabaseURL || !supabaseAnonKey || !serviceRoleKey) {
    return jsonResponse({ error: "Missing required environment variables." }, 500);
  }

  const authHeader = request.headers.get("Authorization");
  if (!authHeader) {
    return jsonResponse({ error: "Missing authorization header." }, 401);
  }

  const userClient = createClient(supabaseURL, supabaseAnonKey, {
    global: {
      headers: {
        Authorization: authHeader,
      },
    },
  });

  const {
    data: { user },
    error: authError,
  } = await userClient.auth.getUser();

  if (authError || !user) {
    return jsonResponse({ error: "Unauthorized." }, 401);
  }

  const adminClient = createClient(supabaseURL, serviceRoleKey, {
    auth: {
      persistSession: false,
      autoRefreshToken: false,
    },
  });

  try {
    const userId = user.id;
    const chatIds = await fetchIds(adminClient, "chats", "id", userId);

    if (chatIds.length > 0) {
      await deleteWhereIn(adminClient, "messages", "chat_id", chatIds);
    }

    await deleteStorageFolder(adminClient, "canvas-images", userId);
    await deleteWhereEq(adminClient, "canvas_elements", "user_id", userId);

    await deleteWhereEq(adminClient, "app_state", "user_id", userId);
    await deleteWhereEq(adminClient, "pages", "user_id", userId);
    await deleteWhereEq(adminClient, "chats", "user_id", userId);
    await deleteWhereEq(adminClient, "notebooks", "user_id", userId);
    await deleteWhereEq(adminClient, "folders", "user_id", userId);

    const { error: deleteUserError } = await adminClient.auth.admin.deleteUser(userId);
    if (deleteUserError) {
      throw deleteUserError;
    }

    return jsonResponse({ success: true }, 200);
  } catch (error) {
    // Supabase errors are not always instances of Error in Deno runtime.
    // Preserve as much detail as possible for the iOS client to display.
    const anyError = error as Record<string, unknown> | null;
    const message =
      (anyError && typeof anyError["message"] === "string" && anyError["message"]) ||
      (anyError && typeof anyError["error"] === "string" && anyError["error"]) ||
      (anyError && typeof anyError["details"] === "string" && anyError["details"]) ||
      (anyError && typeof anyError["hint"] === "string" && anyError["hint"]) ||
      (anyError ? JSON.stringify(anyError) : "") ||
      "Account deletion failed.";

    return jsonResponse({ error: message }, 500);
  }
});

async function fetchIds(
  client: SupabaseClient,
  table: string,
  column: string,
  userId: string,
): Promise<string[]> {
  const { data, error } = await client.from(table)
    .select(column)
    .eq("user_id", userId);

  if (error) {
    if (shouldIgnoreMissingResourceError(error)) {
      return [];
    }
    throw error;
  }

  return (data ?? [])
    .map((row) => String((row as Record<string, unknown>)[column] ?? ""))
    .filter((value) => value.length > 0);
}

async function deleteWhereEq(
  client: SupabaseClient,
  table: string,
  column: string,
  value: string,
) {
  const { error } = await client.from(table).delete().eq(column, value);
  if (error) {
    if (shouldIgnoreMissingResourceError(error)) {
      return;
    }
    throw error;
  }
}

async function deleteWhereIn(
  client: SupabaseClient,
  table: string,
  column: string,
  values: string[],
) {
  if (values.length === 0) {
    return;
  }
  const { error } = await client.from(table).delete().in(column, values);
  if (error) {
    if (shouldIgnoreMissingResourceError(error)) {
      return;
    }
    throw error;
  }
}

async function deleteStorageFolder(
  client: SupabaseClient,
  bucket: string,
  rootPath: string,
) {
  const files = await listStorageFiles(client, bucket, rootPath);
  if (files.length === 0) {
    return;
  }

  const { error } = await client.storage.from(bucket).remove(files);
  if (error) {
    if (shouldIgnoreMissingResourceError(error)) {
      return;
    }
    throw error;
  }
}

async function listStorageFiles(
  client: SupabaseClient,
  bucket: string,
  path: string,
): Promise<string[]> {
  const discovered: string[] = [];
  let offset = 0;

  while (true) {
    const { data, error } = await client.storage.from(bucket).list(path, {
      limit: 100,
      offset,
      sortBy: { column: "name", order: "asc" },
    });

    if (error) {
      if (shouldIgnoreMissingResourceError(error)) {
        return [];
      }
      throw error;
    }

    const entries = data ?? [];
    for (const entry of entries) {
      const entryName = typeof entry.name === "string" ? entry.name : "";
      if (!entryName) {
        continue;
      }

      const childPath = `${path}/${entryName}`;
      if (isStorageFile(entry)) {
        discovered.push(childPath);
      } else {
        discovered.push(...await listStorageFiles(client, bucket, childPath));
      }
    }

    if (entries.length < 100) {
      break;
    }
    offset += entries.length;
  }

  return discovered;
}

function isStorageFile(entry: Record<string, unknown>) {
  return typeof entry["id"] === "string" && entry["id"].length > 0;
}

function shouldIgnoreMissingResourceError(error: unknown) {
  const anyError = error as Record<string, unknown> | null;
  const code = typeof anyError?.["code"] === "string" ? anyError["code"] : "";
  const message = typeof anyError?.["message"] === "string" ? anyError["message"].toLowerCase() : "";
  const details = typeof anyError?.["details"] === "string" ? anyError["details"].toLowerCase() : "";
  const hint = typeof anyError?.["hint"] === "string" ? anyError["hint"].toLowerCase() : "";
  const combined = `${message} ${details} ${hint}`;

  return (
    code === "42P01"
    || code === "PGRST205"
    || combined.includes("does not exist")
    || combined.includes("could not find the table")
    || combined.includes("relation")
    || combined.includes("bucket not found")
  );
}


function jsonResponse(body: Record<string, unknown>, status: number) {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      ...corsHeaders,
      "Content-Type": "application/json",
    },
  });
}
