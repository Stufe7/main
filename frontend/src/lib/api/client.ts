import { env } from '$env/dynamic/public';
import { getSupabase } from '$lib/supabase/client';

export class ApiError extends Error {
	status: number;
	constructor(status: number, message: string) {
		super(message);
		this.status = status;
	}
}

async function accessToken(): Promise<string | null> {
	const supabase = getSupabase();
	if (!supabase) return null;
	const { data } = await supabase.auth.getSession();
	return data.session?.access_token ?? null;
}

export async function api<T>(path: string, init: RequestInit = {}): Promise<T> {
	const token = await accessToken();
	const base = (env.PUBLIC_API_BASE_URL || '').replace(/\/$/, '');
	if (!base) throw new ApiError(503, 'API is not configured');
	const headers = new Headers(init.headers);
	headers.set('Content-Type', 'application/json');
	if (token) headers.set('Authorization', `Bearer ${token}`);
	const response = await fetch(`${base}${path}`, { ...init, headers });
	if (!response.ok) {
		let detail = response.statusText;
		try {
			const body = (await response.json()) as { detail?: string };
			if (body.detail) detail = body.detail;
		} catch {
			/* ignore */
		}
		throw new ApiError(response.status, detail);
	}
	if (response.status === 204) return undefined as T;
	return (await response.json()) as T;
}

export type Membership = {
	entity_id: string;
	entity_name: string;
	role: string;
	status: string;
};

export type SessionInfo = {
	user_id: string;
	email: string | null;
	memberships: Membership[];
	pending_registration: boolean;
	platform_admin: boolean;
};

export type SignupComplete = {
	status: string;
	entity_id?: string | null;
	request_id?: string | null;
	reason_code?: string | null;
	summary?: string | null;
};
