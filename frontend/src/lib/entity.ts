export const ENTITY_KEY = 'stufe7.active_entity_id';

export function activeEntityId(): string | null {
	if (typeof localStorage === 'undefined') return null;
	return localStorage.getItem(ENTITY_KEY);
}

export function setActiveEntityId(id: string) {
	localStorage.setItem(ENTITY_KEY, id);
}

export function ensureActiveEntity(
	memberships: { entity_id: string }[]
): string | null {
	const stored = activeEntityId();
	const match = memberships.find((row) => row.entity_id === stored);
	const id = match?.entity_id || memberships[0]?.entity_id || null;
	if (id) setActiveEntityId(id);
	return id;
}
