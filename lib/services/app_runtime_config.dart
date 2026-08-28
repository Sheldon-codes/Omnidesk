/// Runtime switches for environments where the backend is not available yet.
///
/// Keep this enabled until the production API contract is ready. All auth
/// repository operations remain local while enabled, but page validation and
/// navigation continue to execute normally.
const bool uiOnlyMode = true;
