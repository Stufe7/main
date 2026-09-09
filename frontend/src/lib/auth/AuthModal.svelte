<script lang="ts">
	import { goto } from '$app/navigation';
	import { COUNTRIES } from '$lib/signup/countries';
	import { writeSignupDraft } from '$lib/signup/draft';
	import { formatSignInOtpError } from '$lib/auth/errors';
	import { checkCompanyEmail } from '$lib/companyEmail/allowability';
	import { getSupabase, isSupabaseConfigured } from '$lib/supabase/client';

	type Tab = 'login' | 'signup';
	type Step = 'form' | 'otp';

	let { open = $bindable(false), tab = $bindable<Tab>('login') }: { open?: boolean; tab?: Tab } =
		$props();

	let step = $state<Step>('form');
	let busy = $state(false);
	let error = $state('');
	let info = $state('');

	let loginEmail = $state('');
	let signup = $state({
		firstName: '',
		lastName: '',
		email: '',
		company: '',
		country: 'SG',
		companyUrl: ''
	});
	let otp = $state('');
	let otpEmail = $state('');
	let otpCreateUser = $state(false);
	let lastOtpAt = $state(0);

	const configured = isSupabaseConfigured();
	const OTP_COOLDOWN_MS = 60_000;

	function close() {
		open = false;
		step = 'form';
		error = '';
		info = '';
		otp = '';
	}

	function switchTab(next: Tab) {
		tab = next;
		step = 'form';
		error = '';
		info = '';
		otp = '';
	}

	async function sendOtp(email: string, createUser: boolean) {
		const check = checkCompanyEmail(email);
		if (!check.ok) {
			error = check.reason;
			return;
		}
		if (!configured) {
			error = 'Authentication is not connected in this environment yet.';
			return;
		}
		const supabase = getSupabase();
		if (!supabase) return;
		const trimmed = email.trim();
		const { data: existing } = await supabase.auth.getSession();
		if (existing.session?.user.email?.toLowerCase() === trimmed.toLowerCase()) {
			otpEmail = trimmed;
			otpCreateUser = createUser;
			await continueAfterVerify();
			return;
		}
		if (Date.now() - lastOtpAt < OTP_COOLDOWN_MS) {
			error = 'Wait a minute before requesting another code.';
			return;
		}
		busy = true;
		error = '';
		info = '';
		const { error: otpError } = await supabase.auth.signInWithOtp({
			email: trimmed,
			options: {
				shouldCreateUser: createUser
			}
		});
		busy = false;
		if (otpError) {
			error = formatSignInOtpError(otpError);
			console.error('signInWithOtp failed', otpError);
			return;
		}
		lastOtpAt = Date.now();
		otpEmail = trimmed;
		otpCreateUser = createUser;
		step = 'otp';
		info = `We emailed a sign-in code to ${otpEmail}.`;
	}

	async function continueAfterVerify() {
		const next = otpCreateUser ? '/signup/timezone' : '/app';
		close();
		await goto(next);
	}

	async function submitLogin(event: Event) {
		event.preventDefault();
		await sendOtp(loginEmail, false);
	}

	async function submitSignup(event: Event) {
		event.preventDefault();
		if (!signup.firstName.trim() || !signup.lastName.trim() || !signup.company.trim()) {
			error = 'First name, last name, and company are required.';
			return;
		}
		if (!signup.country) {
			error = 'Country is required.';
			return;
		}
		try {
			const url = new URL(signup.companyUrl.trim());
			if (!['http:', 'https:'].includes(url.protocol) || !url.hostname) throw new Error('bad url');
		} catch {
			error = 'Company URL must start with https://';
			return;
		}
		writeSignupDraft({
			...signup,
			email: signup.email.trim()
		});
		await sendOtp(signup.email, true);
	}

	async function verifyOtp(event: Event) {
		event.preventDefault();
		const supabase = getSupabase();
		if (!supabase) return;
		busy = true;
		error = '';
		const token = otp.trim();
		const types = otpCreateUser ? (['signup', 'email'] as const) : (['email', 'signup'] as const);
		let verifyError: { message: string } | null = null;
		for (const type of types) {
			const result = await supabase.auth.verifyOtp({
				email: otpEmail,
				token,
				type
			});
			verifyError = result.error;
			if (!result.error) break;
		}
		busy = false;
		if (verifyError) {
			error = verifyError.message;
			return;
		}
		const { data: started } = await supabase.auth.getSession();
		if (!started.session?.access_token) {
			error = 'Could not start a session. Try the code again.';
			return;
		}
		await continueAfterVerify();
	}
</script>

{#if open}
	<div class="modal-root">
		<button class="backdrop" type="button" aria-label="Close" onclick={close}></button>
		<div class="dialog" role="dialog" aria-modal="true" aria-labelledby="auth-title">
			<div class="tabs">
				<button class:active={tab === 'login'} type="button" onclick={() => switchTab('login')}
					>Log in</button
				>
				<button class:active={tab === 'signup'} type="button" onclick={() => switchTab('signup')}
					>Sign up</button
				>
				<button class="close" type="button" aria-label="Close" onclick={close}>×</button>
			</div>

			{#if !configured}
				<p class="banner">OTP login will send once Supabase Auth is connected for this environment.</p>
			{/if}

			{#if error}
				<p class="error">{error}</p>
			{/if}
			{#if info}
				<p class="info">{info}</p>
			{/if}

			{#if step === 'form' && tab === 'login'}
				<form onsubmit={submitLogin}>
					<h2 id="auth-title">Log in</h2>
					<label>
						Work email
						<input type="email" bind:value={loginEmail} autocomplete="username" required />
					</label>
					<button class="primary" type="submit" disabled={busy}>Email me a code</button>
				</form>
			{:else if step === 'form' && tab === 'signup'}
				<form onsubmit={submitSignup}>
					<h2 id="auth-title">Create account</h2>
					<div class="row">
						<label>
							First name
							<input type="text" bind:value={signup.firstName} required />
						</label>
						<label>
							Last name
							<input type="text" bind:value={signup.lastName} required />
						</label>
					</div>
					<label>
						Work email
						<input
							type="email"
							bind:value={signup.email}
							placeholder="you@yourcompany.com"
							required
						/>
					</label>
					<label>
						Company
						<input type="text" bind:value={signup.company} required />
					</label>
					<label>
						Country
						<select bind:value={signup.country} required>
							{#each COUNTRIES as country (country.code)}
								<option value={country.code}>{country.name}</option>
							{/each}
						</select>
					</label>
					<label>
						Company URL
						<input
							type="url"
							bind:value={signup.companyUrl}
							placeholder="https://"
							required
						/>
					</label>
					<button class="primary" type="submit" disabled={busy}>Create account</button>
					<p class="legal">By continuing you agree to the Terms and Privacy Policy.</p>
				</form>
			{:else}
				<form onsubmit={verifyOtp}>
					<h2 id="auth-title">Enter the code</h2>
					<p class="hint">Sent to {otpEmail}</p>
					<label>
						Code
						<input
							inputmode="numeric"
							autocomplete="one-time-code"
							bind:value={otp}
							required
						/>
					</label>
					<button class="primary" type="submit" disabled={busy}>Continue</button>
					<button
						class="link"
						type="button"
						disabled={busy}
						onclick={() => sendOtp(otpEmail, otpCreateUser)}
					>
						Resend code
					</button>
					<button class="link" type="button" onclick={() => (step = 'form')}>Use a different email</button>
				</form>
			{/if}
		</div>
	</div>
{/if}

<style>
	.modal-root {
		position: fixed;
		inset: 0;
		z-index: 50;
		display: grid;
		place-items: center;
		padding: 1.5rem;
	}
	.backdrop {
		position: absolute;
		inset: 0;
		border: 0;
		background: rgb(32 38 94 / 0.55);
	}
	.dialog {
		position: relative;
		width: min(28rem, 100%);
		background: white;
		border-radius: 1rem;
		padding: 1.25rem 1.25rem 1.5rem;
		box-shadow: 0 24px 60px rgb(32 38 94 / 0.25);
	}
	.tabs {
		display: flex;
		gap: 0.5rem;
		align-items: center;
		margin-bottom: 1rem;
	}
	.tabs button {
		border: 0;
		background: transparent;
		color: #5b607a;
		font-weight: 600;
		padding: 0.35rem 0.5rem;
		cursor: pointer;
	}
	.tabs button.active {
		color: #20265e;
		box-shadow: inset 0 -2px 0 #2fbf71;
	}
	.close {
		margin-left: auto;
		font-size: 1.4rem;
		line-height: 1;
	}
	form {
		display: grid;
		gap: 0.75rem;
	}
	h2 {
		margin: 0;
		color: #20265e;
		font-size: 1.25rem;
	}
	label {
		display: grid;
		gap: 0.35rem;
		font-size: 0.85rem;
		color: #20265e;
		font-weight: 600;
	}
	input,
	select {
		border: 1px solid #d5d8e6;
		border-radius: 0.6rem;
		padding: 0.65rem 0.75rem;
		font: inherit;
		color: #20265e;
	}
	.row {
		display: grid;
		grid-template-columns: 1fr 1fr;
		gap: 0.75rem;
	}
	.primary {
		border: 0;
		border-radius: 999px;
		background: #20265e;
		color: white;
		font-weight: 650;
		padding: 0.75rem 1rem;
		cursor: pointer;
	}
	.primary:disabled {
		opacity: 0.6;
	}
	.link {
		border: 0;
		background: none;
		color: #20265e;
		text-decoration: underline;
		cursor: pointer;
	}
	.legal,
	.hint {
		margin: 0;
		color: #5b607a;
		font-size: 0.8rem;
		font-weight: 400;
	}
	.error,
	.info,
	.banner {
		margin: 0 0 0.75rem;
		padding: 0.65rem 0.75rem;
		border-radius: 0.6rem;
		font-size: 0.9rem;
	}
	.error {
		background: #fde8e8;
		color: #8a1f1f;
	}
	.info,
	.banner {
		background: #eef7f1;
		color: #1e5c3a;
	}
</style>
