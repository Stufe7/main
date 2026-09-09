export function load({ locals }) {
	return { adminHost: Boolean(locals.adminHost) };
}
