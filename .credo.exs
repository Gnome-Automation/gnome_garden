%{
  configs: [
    %{
      name: "default",
      files: %{
        included: [
          "lib/garden/acquisition/",
          "lib/garden_web/live/acquisition/",
          "lib/garden_web/components/acquisition_ui.ex",
          "test/garden/acquisition/",
          "test/garden_web/live/acquisition_finding_live_test.exs",
          "test/garden_web/live/acquisition_finding_document_live_test.exs"
        ],
        excluded: [~r"/_build/", ~r"/deps/"]
      },
      strict: false,
      color: true,
      checks: %{
        enabled: [
          {ExSlop, []}
        ],
        disabled: []
      }
    }
  ]
}
