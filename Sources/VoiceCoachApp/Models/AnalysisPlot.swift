enum AnalysisPlot: String, CaseIterable, Identifiable {
  case pitch = "Pitch"
  case loudness = "Loudness"
  case spectrum = "Spectrum"

  var id: Self { self }
}
