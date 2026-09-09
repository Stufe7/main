export const PLATFORM_LOGIN_EMAIL = 'admin@stufe7.com';

export function isPlatformLoginEmail(email: string): boolean {
	return email.trim().toLowerCase() === PLATFORM_LOGIN_EMAIL;
}
