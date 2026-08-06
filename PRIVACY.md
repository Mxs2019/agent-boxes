# Privacy information

This document describes the data behavior of the software in this repository. A person or
organization that deploys the service is responsible for its deployment and its legal notices.

## Data that the service stores

The service stores account-key hashes, agent-key hashes, encrypted agent keys, inbox addresses,
cards, email sender addresses, feedback, device identifiers, and Apple Push Notification service
tokens. Cards and feedback can contain personal information that a user or an agent supplies.

The service uses this data to receive, store, synchronize, and display cards. The source code does
not sell personal information and does not add advertising or analytics trackers.

## External services

A deployment uses Cloudflare Workers, D1, Queues, Email Routing, and logs. Push notifications use
Apple Push Notification service. The deployer controls the Cloudflare account and its log-retention
settings.

The website uses local assets and system fonts. It does not request web fonts from a third party.
Restricted email cards can load HTTPS images. An image server can receive the user's IP address and
the time of the request.

## Retention and deletion

Cleared and expired cards stay in D1 so that clients can synchronize changes and show history.
Revoked agents and inboxes also stay in D1. Feedback stays until a user deletes the feedback item or
deletes the account. An invalid push token is deleted when Apple rejects it.

A user can select **Delete account** in the iOS Settings view. The client sends
`DELETE /v1/account`. This action permanently deletes the account, cards, feedback, agents,
inboxes, device registrations, push state, and change records. It also deletes the account key and
cards from that device. A user cannot undo this action.

The repository does not set a retention time for infrastructure logs. A deployer must set and
publish a log-retention time that meets its legal and operational needs.
