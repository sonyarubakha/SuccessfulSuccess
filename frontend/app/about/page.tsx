export default function AboutPage() {
  return (
    <main className="mx-auto max-w-2xl px-6 py-16">
      <h1 className="mb-6 text-3xl font-semibold">SuccessfulSuccess</h1>

      <p className="mb-4">
        SuccessfulSuccess is a web application for managing personal meetings. Users can securely
        sign in and create, view, update, and delete their meetings.
      </p>

      <p className="mb-8">
        Authentication is provided through Amazon Cognito, including email and password sign-in and
        Google sign-in.
      </p>

      <a className="underline" href="/privacy/">
        Privacy Policy
      </a>
    </main>
  )
}
