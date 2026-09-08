const KEY = 'stufe7.signup';

export type SignupDraft = {
	firstName: string;
	lastName: string;
	email: string;
	company: string;
	country: string;
	companyUrl: string;
	timezone?: string;
};

export function readSignupDraft(): SignupDraft | null {
	if (typeof sessionStorage === 'undefined') return null;
	try {
		const raw = sessionStorage.getItem(KEY);
		if (!raw) return null;
		return JSON.parse(raw) as SignupDraft;
	} catch {
		return null;
	}
}

export function writeSignupDraft(draft: SignupDraft) {
	sessionStorage.setItem(KEY, JSON.stringify(draft));
}

export function clearSignupDraft() {
	sessionStorage.removeItem(KEY);
}
