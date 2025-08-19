// Connects to IMAP/SMTP backend

export interface EmailData {
  id: string;
  from: { name: string; address: string };
  to: { name: string; address: string }[];
  subject: string;
  body: string;
  date: number; // Unix timestamp
}

/**
 * Mock function to simulate fetching new emails from an IMAP server.
 * In a real application, this would connect to an IMAP server and retrieve new messages.
 * @returns {Promise<EmailData[]>} A promise that resolves to an array of new emails.
 */
export async function fetchNewEmails(): Promise<EmailData[]> {
  console.log("Checking for new emails (mocked)...");
  // Simulate network delay
  await new Promise(resolve => setTimeout(resolve, 1500));

  // To demonstrate functionality, we can occasionally return a mock email.
  // In a real scenario, this would be based on the server's response.
  if (Math.random() > 0.7) {
    console.log("Found 1 new mock email.");
    return [
      {
        id: `mock-${Date.now()}`,
        from: { name: "Acme Corp", address: "no-reply@acme.com" },
        to: [{ name: "Me", address: "me@example.com" }],
        subject: "Your weekly digest is here!",
        body: "Hello, here is your weekly summary of activities...",
        date: Date.now(),
      }
    ];
  }

  console.log("No new mock emails found.");
  return [];
}

/**
 * Mock function to simulate sending an email via an SMTP server.
 * @param {string} to - The recipient's email address.
 * @param {string} subject - The email subject.
 * @param {string} body - The email body.
 * @returns {Promise<boolean>} A promise that resolves to true if the email was "sent" successfully.
 */
export async function sendEmail(to: string, subject: string, body: string): Promise<boolean> {
  console.log(`Sending email to ${to} (mocked)...`);
  // Simulate network delay
  await new Promise(resolve => setTimeout(resolve, 1000));
  console.log("Email sent successfully (mocked).");
  return true;
}
