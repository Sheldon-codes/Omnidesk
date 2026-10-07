# OmniDesk Agent Privacy Policy

**Draft for legal and operational review — do not publish until the items in “Publication checklist” are completed.**

**Effective date:** [INSERT DATE]  
**Last updated:** [INSERT DATE]

This Privacy Policy explains how **[FULL LEGAL NAME OF OMNIDESK OPERATOR]** ("OmniDesk," "we," "us," or "our") handles personal data when you use the OmniDesk Agent mobile application and related services (together, the “Service”). OmniDesk Agent is a business application for authorized support and sales agents. It connects agents to their organization’s workspace, customer records, tickets, conversations, email, and voice-call workflows.

This policy applies to information processed through the Service. It does not replace the privacy notice of your employer or the organization that invited you, or the privacy notices of communication providers and other services integrated with that organization’s workspace.

## 1. Who is responsible for the data

The organization that provides your OmniDesk workspace (your employer or customer organization) generally decides why and how customer, ticket, and conversation data is used. For that workspace data, the organization is generally the data controller and OmniDesk and its service operator act as processors or service providers under the applicable service agreement and the organization’s instructions.

The OmniDesk operator is generally the controller for agent account administration, authentication, device registration, application security, support, and operation of the Service. The organization may separately control agent activity records and call or ticket records for its employment, operational, compliance, or customer-service purposes. Contact your organization for questions about its use of workspace data or employee monitoring.

**Operator:** [FULL REGISTERED LEGAL NAME]  
**Registered address:** [POSTAL AND PHYSICAL ADDRESS]  
**Privacy contact:** [PRIVACY EMAIL ADDRESS]  
**Data Protection Officer, if appointed:** [NAME/EMAIL OR “NOT APPOINTED”]

## 2. Information we process

Depending on the features your organization enables and how you use them, the Service may process:

### Agent account and workspace information

- Name, email address, account identifier, profile details, role, permissions, team, and workspace membership.
- Authentication information, including access/session tokens and password-reset or account-recovery information. Passwords are submitted to the authentication service; the app stores authentication tokens in platform-protected secure storage, not as ordinary application preferences.
- Workspace settings and account state, such as whether the account is active and which workspace is selected.

### Customer, ticket, and conversation information

- Customer names, phone numbers, email addresses, profile identifiers, and other details supplied by your organization or a customer.
- Ticket identifiers, subjects, descriptions, status, priority, assignment, SLA events, timestamps, notes, and related customer or agent records.
- Messages and communication metadata, including message text, sender and recipient details, channel, timestamps, delivery/read state, replies, reactions or other channel metadata where provided by the backend.
- Email content and metadata, including recipients, subject, message body, quoted history, and attachments. Email drafts may be saved locally on the device in the app’s encrypted local database.
- WhatsApp or other chat content and metadata made available by the organization’s connected channel, including attachments and selected replies.
- Information entered into free-text fields may contain personal or sensitive information. Do not enter information that is not needed for the support task or that your organization has not authorized you to handle.

### Files and other content

If you choose to attach or send content, the Service may access and process the selected image, video, document, audio/voice note, contact card, or other supported file, along with its filename, MIME type, size, caption, and upload status. The app uses platform pickers for media and files where available. Selected files are transmitted to the organization’s backend or configured communication service for the requested operation. Pending message attachments may be temporarily queued on the device until sending succeeds or the queue is cleared.

### Location and contacts, when you choose to use those features

- If you choose to share your location in a conversation, the app requests location permission, obtains a location fix, and includes a location link or location information in the message sent through the workspace. The app does not need continuous background location for this sharing flow.
- If you choose to share a contact, the app requests the platform permission required for the contact picker, lets you select a contact, and may convert that selection into a vCard to send in the conversation. The app does not need to upload your entire address book for this feature.
- The Android app declares contact and location permissions for supported features and calling/account setup. You can deny or revoke optional permissions in your device settings; the corresponding feature may then be unavailable.

### Voice-call information

- Calling account and installation identifiers, call direction, call/session identifiers, phone numbers, call status, timestamps, duration, and diagnostics needed to place, receive, route, and troubleshoot calls.
- Microphone audio is captured during a call after the call is answered or placed and the required permission/audio readiness is granted. Audio is transmitted to the other call participant through the configured telephony/WebRTC service. The mobile client’s WebRTC implementation is a live media path; it does not intentionally save a local call-audio recording.
- Call records returned by the backend may include a recording link or transcript. The app can display or access those backend-provided fields when available. Whether calls are recorded or transcribed is controlled by the organization and/or its telephony provider, not established by the mobile client alone. Ask your organization whether recording or transcription is enabled and how it is disclosed to callers.
- WebRTC signaling and network setup may process IP/network information, ICE candidates, and media connection metadata. The signaling gateway and any STUN/TURN relays are supplied through the call configuration service; the client does not invent its own relay endpoints.

### Device, installation, and service information

- A random app installation identifier; platform and app version/build; device model/name and operating-system version; and push-routing tokens needed to register the device for notifications and incoming calls.
- Firebase Cloud Messaging (FCM), Apple Push Notification service (APNs), and, on iOS, PushKit VoIP push tokens may be used for call offers, call state/cancellation, and notifications. Push payloads may contain routing identifiers and limited call or notification details. The operating system may show notification content on a lock screen depending on your device settings.
- Basic technical and security information such as request time, response status, error type, and connection diagnostics may be processed to operate and secure the Service. The app has no dedicated third-party analytics or crash-reporting SDK identified in the reviewed client configuration; this does not exclude operational logs maintained by the backend, hosting provider, operating system, or integrated providers.

## 3. How we use information

We use information, as appropriate, to:

1. Authenticate agents, maintain sessions, enforce workspace access, and prevent unauthorized use.
2. Display and synchronize customer, ticket, email, and conversation records; support search, assignment, replies, attachments, and related customer-service tasks.
3. Route incoming and outgoing calls, establish live audio, display call controls and history, and report call outcomes to the workspace backend.
4. Deliver push notifications and incoming-call alerts to registered devices.
5. Save and restore drafts, encrypted local cache, and pending outgoing messages where necessary for normal app operation.
6. Diagnose errors, maintain service availability, protect accounts and systems, investigate abuse, and comply with legal obligations.
7. Provide support and respond to privacy or account requests.

We do not use workspace conversation content to serve advertising. The client repository does not show a dedicated advertising SDK or a dedicated analytics/crash-reporting SDK. The organization and connected providers may use their own tools and policies.

## 4. Legal bases

Where applicable law requires a legal basis, the relevant controller determines and documents it. Depending on the context, processing may be necessary to perform an employment or service relationship, provide the requested communications service, comply with a legal obligation, protect legitimate business or security interests, or act on consent for optional device permissions and user-initiated sharing. An organization using OmniDesk is responsible for identifying its lawful basis for customer and employee data and giving its own required notices.

Where processing relies on consent, you may withdraw it through the relevant app or device setting. Withdrawal does not invalidate processing that occurred before withdrawal and may prevent the associated feature from working.

## 5. How information is shared

Information may be shared only as needed for the purposes above with:

- **Your organization and workspace users:** agents, supervisors, administrators, and authorized staff with access to the relevant workspace, ticket, or call.
- **OmniDesk’s backend and infrastructure providers:** to host the service, authenticate accounts, store/synchronize workspace data, process requests, and provide support. The operator must identify the actual hosting and infrastructure providers in its vendor/subprocessor list.
- **Communication and calling providers configured by the organization:** including WhatsApp/Meta or other messaging channel providers, email providers, and Africa’s Talking for call signaling/media, where those channels are enabled. Those providers process information under their own terms and privacy notices and the organization’s configuration.
- **Push providers:** Google Firebase Cloud Messaging and Apple APNs/PushKit to deliver push notifications and incoming-call signaling to registered devices.
- **Device operating-system services:** Android Telecom or Apple CallKit/PushKit as necessary to present and manage calls and their system controls.
- **Professional advisers, regulators, law enforcement, or other parties:** where required by law, necessary to protect rights and safety, or needed to establish or defend legal claims.
- **A successor entity:** in a merger, acquisition, restructuring, or transfer of the Service, subject to applicable privacy requirements.

We do not sell personal information. We do not share it with advertisers for cross-context behavioral advertising through the mobile client.

## 6. International transfers

The Service may involve processing in Kenya and in other countries where the operator, your organization, or its selected infrastructure, communications, push, email, or calling providers operate. The client code does not establish the physical hosting locations or complete transfer mechanism for the production backend. Before publication, the operator must identify relevant countries and ensure that each transfer has the safeguards required by applicable law, including the Kenya Data Protection Act and regulations where applicable. Where required, safeguards may include an adequacy basis, contractual safeguards, or another lawful transfer mechanism.

Contact [PRIVACY EMAIL] or your organization for information about the countries and safeguards applicable to your workspace.

## 7. Retention

We retain personal data only for as long as necessary for the purposes described here, under the organization’s documented instructions and retention schedule, to meet legal obligations, resolve disputes, enforce agreements, and protect the Service. The actual retention periods for backend ticket, message, email, call, recording, and transcript data are determined by the organization and applicable provider configuration; they must be documented in the organization’s retention schedule.

On the device, authentication credentials are stored using platform secure storage; app cache, email drafts, and pending message data may remain in an encrypted local database until deleted, cleared by the app, removed during logout where supported, or removed when the application data is erased/uninstalled. Push tokens and installation registrations are retained while needed to route notifications and calls and should be revoked or unregistered when the account/device is removed. Backup behavior depends on the operating system and the organization’s device-management settings.

When information is no longer required, it should be deleted or de-identified, subject to legally required retention and secure-backup expiry. Ask your workspace administrator for the retention period that applies to customer communications and call records.

## 8. Security

The app uses authenticated API requests, platform-protected secure storage for session credentials, and an encrypted SQLCipher database for supported local cache/draft/outbox data. Network connections use HTTPS for the backend API and secure transport for configured signaling/media services. Access to workspace information is governed by authentication and workspace permissions.

No electronic system is completely secure. Organizations should use managed devices where appropriate, keep operating systems and the app updated, protect device unlock credentials, restrict access to workspace accounts, and promptly report lost devices or suspected account compromise. Do not share passwords, access tokens, capability tokens, or call credentials.

## 9. Your choices and rights

You can:

- Review, correct, or request deletion of account information through your workspace administrator or [PRIVACY EMAIL].
- Disable notifications, microphone, camera, photos/files, contacts, or location permissions in your device settings. Call, attachment, contact-sharing, or location-sharing features may not work without the relevant permission.
- Sign out to end the app session on the device. If you use “log out everywhere,” the app requests the corresponding backend action; local sign-out is performed even if the network is unavailable.
- Ask your organization to access, correct, object to, restrict, delete, or export workspace data, as applicable. You may also have rights to withdraw consent and complain to the relevant supervisory authority.

Under Kenya’s Data Protection Act, data subjects have rights including to be informed, access their data, object to processing, and seek correction or deletion of false or misleading data, subject to statutory conditions and exceptions. If the GDPR or another law applies, additional rights may include portability, restriction, erasure, and the right to lodge a complaint with a supervisory authority. The applicable controller will respond within the timelines required by law. We may need to verify identity and coordinate with the workspace organization before fulfilling a request.

For customer or end-user information held in an organization’s workspace, contact that organization first. If your request concerns OmniDesk’s own account or device-registration processing, contact [PRIVACY EMAIL]. You may also complain to the [Office of the Data Protection Commissioner in Kenya](https://www.odpc.go.ke/rights-of-a-data-subject/) or the supervisory authority applicable to you.

## 10. Children and sensitive information

OmniDesk Agent is designed for authorized business users, not for children to create their own accounts. A support organization may nevertheless use the Service to communicate with a child or process information about a child as part of a customer-service case. The organization must ensure it has an appropriate lawful basis, notices, permissions, and safeguards for that processing. Do not enter sensitive personal data unless it is necessary for the case and your organization has authorized its handling.

## 11. Automated decisions

The mobile app is not designed to make decisions about people that produce legal or similarly significant effects solely by automated processing. Ticket routing, prioritization, SLA status, or other backend automation may be configured by an organization. The organization is responsible for explaining any such decision-making and providing applicable rights or review mechanisms.

## 12. Third-party services and links

The Service connects to third-party communication, push, telephony, operating-system, and infrastructure services. Their processing is governed by their own terms and privacy notices. An organization may independently connect additional channels or providers. OmniDesk does not control the privacy practices of third-party services; consult the provider information supplied by your organization.

## 13. Changes to this policy

We may update this policy as the Service, providers, or applicable laws change. We will update the “Last updated” date and provide notice through the app, the organization, or another reasonable channel when required. Material changes will be communicated before they take effect where applicable law requires it.

## 14. Contact

Questions, requests, or complaints about this policy may be sent to:

**[FULL LEGAL NAME OF OMNIDESK OPERATOR]**  
**Privacy email:** [PRIVACY EMAIL ADDRESS]  
**Postal address:** [POSTAL ADDRESS]  
**Data Protection Officer:** [CONTACT DETAILS, IF APPOINTED]

For workspace customer records, messages, tickets, or call records, contact the organization that manages your OmniDesk workspace.

---

## Publication checklist

This draft reflects the mobile client code reviewed on 7 October 2026. Complete and validate all of the following before publishing it or submitting it to an app store:

1. Replace the operator identity, address, privacy email, DPO details, effective date, and complaint contact.
2. Confirm the legal controller/processor roles in the customer contract and agent-employment context; add a data-processing agreement and organization-facing end-user notice as needed.
3. Obtain the backend’s actual data inventory: API/server logs, IP addresses, audit logs, auth events, analytics/monitoring, support tooling, backups, tenant boundaries, and deletion workflows.
4. Publish the actual hosting/subprocessor list, country/location of processing, transfer safeguards, and provider links. Confirm the roles of Firebase/Google, Apple, Africa’s Talking, Meta/WhatsApp, email providers, and any additional channel vendors for the production deployment.
5. Confirm retention periods for account/device records, tickets, messages, attachments, email, call logs, recordings/transcripts, API/security logs, backups, local drafts, and pending outbox data. The app code alone cannot determine these schedules.
6. Confirm whether any workspace records, call audio, recordings, or transcripts contain sensitive personal data or children’s data, and document the lawful basis, notices, access controls, and retention applicable to them.
7. Verify permission prompts and actual collection on each supported release build, including Android contacts/location/phone permissions and iOS location/contact/photo/camera/microphone permissions. The manifest may include permissions for features that users do not enable.
8. Decide whether the app will provide in-app privacy access/deletion requests and an account/device revocation workflow; document any limits due to organization-controlled data.
9. Have qualified privacy counsel review the final policy against the Kenya Data Protection Act, the Data Protection (General) Regulations, 2021, any applicable sector rules, and other laws for the locations of agents and customers.

### Engineering observations (not publication text)

- The app declares Firebase Messaging and initializes it for push/call delivery. It registers installation and push-token data with the authenticated backend.
- The app stores access/session tokens with platform secure storage and uses an encrypted SQLCipher local database for supported cache, drafts, and pending-message data.
- The client sends support replies and selected attachments to its backend API. Media size/type/filename and message text can be included in backend requests; the API diagnostic redactor is designed to redact message, media, token, password, SDP, and credential fields.
- The app reads call history fields that can include phone number, call duration, transcript, and recording URL from the backend. Confirm call recording/transcription policy and responsibility with the organization and telephony provider.
- The reviewed Flutter dependency list does not show a dedicated analytics or crash-reporting package. Verify transitive native SDKs and production backend/hosting telemetry before making a public “no analytics” claim.
- Production hosting region, backend retention, processor contracts, and full subprocessors cannot be verified from this mobile repository.
