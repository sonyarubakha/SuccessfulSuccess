export default function PrivacyPage() {
  return (
    <main className="mx-auto max-w-2xl px-6 py-16">
      <h1 className="mb-6 text-3xl font-semibold">Privacy Policy</h1>

      <p className="mb-4">
        SuccessfulSuccess uses authentication information provided by Amazon Cognito and, when
        Google sign-in is used, basic profile information provided by Google.
      </p>

      <p className="mb-4">
        The application may use your email address and basic account information to identify your
        account and provide access to your meetings.
      </p>

      <p className="mb-4">SuccessfulSuccess does not sell personal information to third parties.</p>

      <p className="mb-8">
        Authentication data is used only for signing in and operating the application.
      </p>

      <a className="underline" href="/about/">
        Back to SuccessfulSuccess
      </a>
    </main>
  )
}
