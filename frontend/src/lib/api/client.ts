import { env } from '$env/dynamic/public';
import { activeEntityId, ensureActiveEntity } from '$lib/entity';
import { getSupabase } from '$lib/supabase/client';

export class ApiError extends Error {
	status: number;
	constructor(status: number, message: string) {
		super(message);
		this.status = status;
	}
}

const TOKEN_SKEW_MS = 30_000;
const SESSION_TTL_MS = 15_000;

let cachedToken: { value: string; exp: number } | null = null;
let sessionCache: { data: SessionInfo; at: number } | null = null;
let sessionInflight: Promise<SessionInfo> | null = null;

function jwtExpMs(token: string): number {
	try {
		const part = token.split('.')[1];
		if (!part) return 0;
		const padded = part.replace(/-/g, '+').replace(/_/g, '/');
		const json = JSON.parse(atob(padded)) as { exp?: number };
		return Number(json.exp || 0) * 1000;
	} catch {
		return 0;
	}
}

export function rememberAccessToken(token: string | null) {
	if (!token) {
		cachedToken = null;
		return;
	}
	cachedToken = { value: token, exp: jwtExpMs(token) };
}

export function clearApiCaches() {
	cachedToken = null;
	sessionCache = null;
	sessionInflight = null;
}

async function accessToken(): Promise<string | null> {
	if (cachedToken && cachedToken.exp - TOKEN_SKEW_MS > Date.now()) {
		return cachedToken.value;
	}
	const supabase = getSupabase();
	if (!supabase) return null;
	const { data } = await supabase.auth.getSession();
	const token = data.session?.access_token ?? null;
	rememberAccessToken(token);
	return token;
}

function isGetSession(path: string, init: RequestInit): boolean {
	if (path !== '/v1/session') return false;
	return (init.method || 'GET').toUpperCase() === 'GET';
}

async function authorizedFetch(path: string, init: RequestInit = {}, json = true): Promise<Response> {
	const token = await accessToken();
	const base = (env.PUBLIC_API_BASE_URL || '').replace(/\/$/, '');
	if (!base) throw new ApiError(503, 'API is not configured');
	const headers = new Headers(init.headers);
	if (json) headers.set('Content-Type', 'application/json');
	if (token) headers.set('Authorization', `Bearer ${token}`);
	const entity = activeEntityId();
	if (entity) headers.set('X-Entity-Id', entity);
	const response = await fetch(`${base}${path}`, { ...init, headers });
	if (!response.ok) {
		if (response.status === 401) clearApiCaches();
		let detail = response.statusText;
		try {
			const body = (await response.json()) as { detail?: string };
			if (body.detail) detail = body.detail;
		} catch {
			/* ignore */
		}
		throw new ApiError(response.status, detail);
	}
	return response;
}

export async function apiDownload(path: string, filename: string): Promise<void> {
	const response = await authorizedFetch(path, {}, false);
	const blob = await response.blob();
	const url = URL.createObjectURL(blob);
	const link = document.createElement('a');
	link.href = url;
	link.download = filename;
	link.click();
	URL.revokeObjectURL(url);
}

export async function apiUpload<T>(path: string, file: File): Promise<T> {
	const body = new FormData();
	body.append('file', file);
	const response = await authorizedFetch(path, { method: 'POST', body }, false);
	return (await response.json()) as T;
}

async function apiRaw<T>(path: string, init: RequestInit = {}): Promise<T> {
	const response = await authorizedFetch(path, init);
	if (response.status === 204) return undefined as T;
	return (await response.json()) as T;
}

export async function api<T>(path: string, init: RequestInit = {}): Promise<T> {
	if (!isGetSession(path, init)) {
		return apiRaw<T>(path, init);
	}
	if (sessionCache && Date.now() - sessionCache.at < SESSION_TTL_MS) {
		return sessionCache.data as T;
	}
	if (!sessionInflight) {
		sessionInflight = apiRaw<SessionInfo>('/v1/session')
			.then((data) => {
				sessionCache = { data, at: Date.now() };
				return data;
			})
			.finally(() => {
				sessionInflight = null;
			});
	}
	return sessionInflight as Promise<T>;
}

async function ensureAppSession(): Promise<SessionInfo> {
	const session = await api<SessionInfo>('/v1/session');
	if (!ensureActiveEntity(session.memberships)) {
		throw new ApiError(403, 'No entity membership.');
	}
	return session;
}

export async function withActiveEntity<T>(load: () => Promise<T>): Promise<T> {
	if (activeEntityId()) {
		const [, result] = await Promise.all([ensureAppSession(), load()]);
		return result;
	}
	await ensureAppSession();
	return load();
}

export type Membership = {
	entity_id: string;
	entity_name: string;
	role: string;
	status: string;
};

export type Member = {
	user_id: string;
	email: string;
	first_name: string | null;
	last_name: string | null;
	role: string;
	status: string;
};

export type SessionInfo = {
	user_id: string;
	email: string | null;
	memberships: Membership[];
	pending_registration: boolean;
	platform_admin: boolean;
	privacy_operator: boolean;
	email_sync_error?: string | null;
};

export type SignupComplete = {
	status: string;
	entity_id?: string | null;
	request_id?: string | null;
	reason_code?: string | null;
	summary?: string | null;
};

export type Company = {
	id: string;
	company_name: string;
	legal_name: string | null;
	status: string;
	record_state: string;
	country: string | null;
	website: string | null;
	notes: string | null;
	owner_user_id: string | null;
	next_action_due_date: string | null;
};

export type Contact = {
	id: string;
	company_id: string;
	company_name: string | null;
	first_name: string;
	last_name: string;
	job_title: string | null;
	email: string | null;
	telephone: string | null;
	mobile: string | null;
	linkedin_url: string | null;
	notes: string | null;
	record_state: string;
	next_action_due_date: string | null;
};

export type Activity = {
	id: string;
	company_id: string;
	company_name: string | null;
	contact_id: string | null;
	activity_type: string;
	activity_date: string;
	subject: string;
	description: string | null;
	outcome: string | null;
	source_action_id: string | null;
};

export type ActionItem = {
	id: string;
	company_id: string;
	company_name: string | null;
	contact_id: string | null;
	owner_user_id: string;
	action_type: string;
	description: string;
	due_date: string | null;
	due_time: string | null;
	priority: string;
	status: string;
	source_activity_id: string | null;
};

export type HomeInfo = {
	timezone: string;
	today: string;
	actions: ActionItem[];
	attention_count: number;
	handovers: {
		id: string;
		company_id: string;
		company_name: string;
		reason: string;
		created_at: string;
	}[];
};
