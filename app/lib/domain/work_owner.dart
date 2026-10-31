/// Which side a step belongs to: the engineer, or the contractor.
///
/// The Plan screen shows the engineer's own steps — the Kashfeya site survey and the SEC
/// close-out paperwork. The Follow-up screen shows everything the contractor carries out,
/// including applying for the tasreeh. Keeping the list in one place means the two screens
/// cannot drift apart and start listing the same orders again.
const Set<String> engineerSteps = {
  'kashfeya', // the engineer's site survey
  'form_190', // SEC close-out forms and certificate
  'form_200',
  'certificate',
  'documents_submitted',
};

/// True when [idOrKey] is the engineer's work. Accepts a step key or a step instance id such
/// as `compaction@<segment id>`, which is how per-segment steps are identified.
bool isEngineerStep(String idOrKey) => engineerSteps.contains(idOrKey.split('@').first);
