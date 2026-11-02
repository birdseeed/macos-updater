# Synthetic billing vectors

PAT-2645 only, not Paddle data or signature compatibility. Keys are explicit fake bytes (0x42 repeated 32 times). Bodies and canonical projections are exact bytes, without a trailing newline. Python standard-library JSON (restricted integer domain), hashlib and hmac independently generated the pinned literals before implementation. Notification alone is excluded; all accepted data is retained. Raw label is a deliberate privacy canary.

Default composition refuses. No household, purchase, entitlement, provider or installation authority is established. No cleanup or real financial/privacy retention schedule is introduced.
