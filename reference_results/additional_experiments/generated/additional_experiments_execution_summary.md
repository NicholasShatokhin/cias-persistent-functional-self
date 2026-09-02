# Additional experiments execution summary

Status: `COMPLETE`

This summary is generated from the completed additional-experiment seed ranges defined in the repository protocol.

## CIAS Full vs anchor lesion
- **identity_continuity**: mean advantage 0.7477, 95% bootstrap CI [0.6628, 0.8286], n=30
- **lure_rejection**: mean advantage 0.5098, 95% bootstrap CI [0.4536, 0.5633], n=30

## CIAS Full vs generic recurrent estimator

Differences are CIAS Full minus the generic recurrent estimator; negative values favor the generic estimator.
- **continuity_advantage**: mean difference -0.0506, 95% CI [-0.0676, -0.0345], n=30
- **lure_rejection_advantage**: mean difference -0.0218, 95% CI [-0.0314, -0.0130], n=30

## Parameter sensitivity
- Prespecified settings: 27.
- Both primary effect signs preserved: 25/27 (92.6%).
- Both primary pointwise 95% CIs above zero: 25/27 (92.6%).
- Both 95% simultaneous max-bootstrap intervals above zero: 24/27 (88.9%).
- Correct effect direction in at least 3/4 profiles for both outcomes: 25/27 (92.6%).
- Identity advantage: median 0.7602; worst tested setting -0.2476.
- Lure-rejection advantage: median 0.5237; worst tested setting 0.2110.

All prespecified settings are retained in the summary, including failure regions observed on held-out data.
