import { env } from '$env/dynamic/public';
import { activeEntityId } from '$lib/entity';
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
	const entity = activeEntityId();
	if (entity) headers.set('X-Entity-Id', entity);
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
