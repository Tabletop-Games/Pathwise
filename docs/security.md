# Security

Only Cloud Run's runtime identity receives Firestore and Play publisher API access. The OAuth secret belongs in Secret Manager. Android needs public IDs plus the HTTPS verifier origin. Keep signing material off-repository.

Receipt handling rejects arbitrary products, pending/cancelled purchases, mismatched accounts and invalid quantities. Firestore transaction claims prevent the same token from crediting twice. AdMob SSV verifies the original encoded callback bytes before trusting reward fields and uses expiring nonce records to bind the placement. Avoid logging bearer values, purchase tokens, OAuth codes and callback query strings.

Offline save integrity prevents accidental double credit; it is not a tamper-proof client trust boundary. A production ranked mode requires authoritative verification and attestation. Launch payment settings should account for the documented gaps in refunds and recovery.
