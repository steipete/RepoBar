import Foundation
@testable import repobarcli
@testable import RepoBarCore
import Testing

struct WorkflowRunOutputTests {
    @Test(arguments: ["Deploy", "CI", "", "  \n"])
    func `workflow identity survives decoding and JSON without redundant keys`(workflowName: String) throws {
        let response: [String: Any] = [
            "workflow_runs": [[
                "id": 1,
                "name": workflowName,
                "display_title": "CI",
                "html_url": "https://github.com/acme/widget/actions/runs/1",
                "status": "completed",
                "conclusion": "success"
            ]]
        ]
        let data = try JSONSerialization.data(withJSONObject: response)
        let run = try #require(GitHubClient.decodeRecentWorkflowRuns(from: data).first)
        let encoded = try JSONEncoder().encode(WorkflowRunOutput(run))
        let output = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])

        #expect(output["name"] as? String == "CI")
        if workflowName == "Deploy" {
            #expect(output["workflowName"] as? String == "Deploy")
        } else {
            #expect(output.keys.contains("workflowName") == false)
        }
    }

    @Test(arguments: ["Deploy", nil] as [String?])
    func `workflow table retains titles and adds distinct workflow names`(workflowName: String?) throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let run = try RepoWorkflowRunSummary(
            name: "Fix cache refresh",
            workflowName: workflowName,
            url: #require(URL(string: "https://github.com/acme/widget/actions/runs/1")),
            updatedAt: now,
            status: .passing,
            conclusion: "success",
            branch: "main",
            event: "push",
            actorLogin: "alice",
            actorAvatarURL: nil,
            runNumber: 1
        )
        let output = workflowRunsTableLines([run], useColor: false, includeURL: false, now: now)
            .joined(separator: "\n")

        #expect(output.contains("Fix cache refresh"))
        #expect(output.contains("main"))
        if workflowName != nil {
            #expect(output.contains("Deploy · Fix cache refresh"))
        } else {
            #expect(output.contains(" · ") == false)
        }
    }
}
