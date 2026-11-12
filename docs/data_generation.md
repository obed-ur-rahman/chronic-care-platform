# Data Generation

Synthetic patient data is generated with Synthea and is not committed to git.
Anyone can regenerate the identical dataset using the settings below.

- **Synthea release:** [name of the release you downloaded, e.g. master-branch-latest]
- **Java version:** [output of java -version]
- **Generated on:** [today's date]
- **Seed:** 42
- **Patients generated:** [number from the count command below]

## Command

java -jar synthea-with-dependencies.jar -p 1000 -s 42 -a 30-80 --exporter.csv.export true --exporter.fhir.export false --exporter.years_of_history 0 --exporter.baseDirectory ./data/raw/synthea "New York"

## Notes

- Full lifetime history exported (years_of_history = 0) to support lookback windows.
- Ages 30-80 at end of simulation, the population at risk for type 2 diabetes, hypertension and CKD.
- Patient count exceeds 1,000 because Synthea also keeps patients who died during the simulation.