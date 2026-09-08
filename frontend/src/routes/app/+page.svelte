<script lang="ts">
	import { goto } from '$app/navigation';
	import { onMount } from 'svelte';
	import { auth, requireSession, signOut } from '$lib/auth/session.svelte';
	import { readSignupDraft } from '$lib/signup/draft';

	let draft = $state<ReturnType<typeof readSignupDraft>>(null);

	onMount(async () => {
		draft = readSignupDraft();
		const email = await requireSession();
		if (!email) await goto('/');
	});

	async function leave() {
		await signOut();
		await goto('/');
	}
</script>

<svelte:head>
	<title>Signed in — Stufe7</title>
</svelte:head>

<div class="page">
	<header>
		<img src="/stufe7-logo.svg" alt="Stufe7" class="wordmark" />
		{#if auth.email}
			<p class="who">{auth.email}</p>
			<button type="button" class="ghost" onclick={leave}>Sign out</button>
		{/if}
	</header>

	<section class="card">
		<h1>You’re signed in</h1>
		{#if draft}
			<p>
				{draft.company} is ready for the next signup steps: company identity check, then the workspace.
				Those are not live yet. Your details stay on this device until provisioning is built.
			</p>
			<dl>
				<div><dt>Name</dt><dd>{draft.firstName} {draft.lastName}</dd></div>
				<div><dt>Company</dt><dd>{draft.company}</dd></div>
				<div><dt>Country</dt><dd>{draft.country}</dd></div>
				<div><dt>Website</dt><dd>{draft.companyUrl}</dd></div>
				{#if draft.timezone}
					<div><dt>Timezone</dt><dd>{draft.timezone}</dd></div>
				{/if}
			</dl>
		{:else}
			<p>
				The login worked. Company workspaces are not provisioned yet, so there is no CRM home to open.
			</p>
		{/if}
	</section>
</div>

<style>
	.page {
		min-height: 100vh;
		padding: 1.25rem 1rem 3rem;
	}
	header,
	.card {
		width: min(40rem, 100%);
		margin-inline: auto;
	}
	header {
		display: flex;
		flex-wrap: wrap;
		align-items: center;
		gap: 0.75rem 1rem;
		margin-bottom: 1.5rem;
	}
	.wordmark {
		height: 1.75rem;
		width: auto;
	}
	.who {
		margin: 0 auto 0 0;
		color: #5b607a;
		font-size: 0.95rem;
	}
	.card {
		background: white;
		border-radius: 1rem;
		padding: 1.5rem;
		box-shadow: 0 10px 30px rgb(32 38 94 / 0.06);
	}
	h1 {
		margin: 0 0 0.75rem;
		font-size: 1.5rem;
	}
	p {
		margin: 0 0 1rem;
		color: #3c4160;
	}
	dl {
		margin: 0;
		display: grid;
		gap: 0.65rem;
	}
	dl div {
		display: grid;
		grid-template-columns: 7rem 1fr;
		gap: 0.5rem;
	}
	dt {
		color: #5b607a;
		font-size: 0.85rem;
	}
	dd {
		margin: 0;
		font-weight: 650;
	}
	.ghost {
		border: 1px solid #20265e;
		background: white;
		color: #20265e;
		border-radius: 999px;
		padding: 0.45rem 0.9rem;
		font: inherit;
		font-weight: 650;
		cursor: pointer;
	}
</style>
