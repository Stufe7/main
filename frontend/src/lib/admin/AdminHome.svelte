<script lang="ts">
	import { goto } from '$app/navigation';
	import { onMount } from 'svelte';
	import { PLATFORM_LOGIN_EMAIL } from '$lib/admin/login';
	import AuthModal from '$lib/auth/AuthModal.svelte';
	import { requireSession } from '$lib/auth/session.svelte';

	let authOpen = $state(true);
	let authTab = $state<'login' | 'signup'>('login');

	onMount(async () => {
		if (await requireSession()) {
			await goto('/platform');
		}
	});
</script>

<div class="gate">
	<img src="/stufe7-logo.svg" alt="Stufe7" />
	<h1>Platform admin</h1>
	<p>Separate from the CRM. Only {PLATFORM_LOGIN_EMAIL} can sign in. A one-time code is emailed.</p>
</div>

<AuthModal
	bind:open={authOpen}
	bind:tab={authTab}
	allowSignup={false}
	nextPath="/platform"
	dismissible={false}
	allowedEmail={PLATFORM_LOGIN_EMAIL}
/>

<style>
	.gate {
		min-height: 100vh;
		display: grid;
		align-content: start;
		justify-items: center;
		gap: 0.75rem;
		padding: 3rem 1.25rem 8rem;
		text-align: center;
		color: #20265e;
	}
	img {
		height: 1.75rem;
		width: auto;
	}
	h1 {
		margin: 1.5rem 0 0;
		font-size: 1.6rem;
	}
	p {
		margin: 0;
		max-width: 26rem;
		color: #5b607a;
	}
</style>
