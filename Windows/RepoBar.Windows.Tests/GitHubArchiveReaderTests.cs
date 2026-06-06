using System.Net;
using System.Text;
using System.Text.Json;
using Microsoft.Data.Sqlite;
using Xunit;

namespace RepoBar.Windows.Tests;

public sealed class GitHubArchiveReaderTests
{
    [Fact]
    public void Archive_reader_returns_recent_open_issue_and_pull_threads()
    {
        var databasePath = CreateArchiveDatabase();
        try
        {
            using (var connection = OpenWritable(databasePath))
            {
                CreateThreadsTable(connection);
                InsertThread(
                    connection,
                    repository: "owner/name",
                    kind: "issue",
                    number: 41,
                    title: "Older bug",
                    state: "open",
                    updatedAt: "2026-05-31T12:00:00Z",
                    url: "https://github.com/owner/name/issues/41",
                    author: "bob");
                InsertThread(
                    connection,
                    repository: "owner/name",
                    kind: "issue",
                    number: 42,
                    title: "Crash on startup",
                    state: "open",
                    updatedAt: "2026-06-01T12:00:00Z",
                    url: "https://github.com/owner/name/issues/42",
                    author: "alice");
                InsertThread(
                    connection,
                    repository: "owner/name",
                    kind: "issue",
                    number: 43,
                    title: "Closed bug",
                    state: "closed",
                    updatedAt: "2026-06-02T12:00:00Z",
                    url: "https://github.com/owner/name/issues/43",
                    author: "zoe");
                InsertThread(
                    connection,
                    repository: "owner/name",
                    kind: "pull_request",
                    number: 7,
                    title: "Add Windows archive fallback",
                    state: "open",
                    updatedAt: "2026-06-02T13:00:00Z",
                    url: "https://github.com/owner/name/pull/7",
                    author: "carol");
            }

            var reader = new WindowsGitHubArchiveReader(databasePath);
            var repository = new RepositoryRef { Owner = "owner", Name = "name" };

            var issues = reader.RecentIssues(repository, limit: 5);
            var pulls = reader.RecentPulls(repository, limit: 5);

            Assert.Collection(
                issues,
                issue =>
                {
                    Assert.Equal("#42 Crash on startup", issue.Title);
                    Assert.Equal("https://github.com/owner/name/issues/42", issue.Url);
                    Assert.Contains("alice", issue.Subtitle);
                },
                issue => Assert.Equal("#41 Older bug", issue.Title));
            var pull = Assert.Single(pulls);
            Assert.Equal("#7 Add Windows archive fallback", pull.Title);
            Assert.Equal("https://github.com/owner/name/pull/7", pull.Url);
            Assert.Contains("carol", pull.Subtitle);
        }
        finally
        {
            DeleteDatabase(databasePath);
        }
    }

    [Fact]
    public void Archive_reader_builds_fallback_urls_from_active_enterprise_host()
    {
        var databasePath = CreateArchiveDatabase();
        try
        {
            using (var connection = OpenWritable(databasePath))
            {
                CreateThreadsTable(connection);
                InsertThread(
                    connection,
                    repository: "owner/name",
                    kind: "issue",
                    number: 44,
                    title: "Enterprise archive issue",
                    state: "open",
                    updatedAt: "2026-06-03T12:00:00Z",
                    url: null,
                    author: "alice");
            }

            var reader = new WindowsGitHubArchiveReader(databasePath, "https://GitHub.Enterprise.test/org");
            var repository = new RepositoryRef { Owner = "owner", Name = "name" };

            var issue = Assert.Single(reader.RecentIssues(repository, limit: 5));

            Assert.Equal("#44 Enterprise archive issue", issue.Title);
            Assert.Equal("https://github.enterprise.test/owner/name/issues/44", issue.Url);
        }
        finally
        {
            DeleteDatabase(databasePath);
        }
    }

    [Fact]
    public void CreateSmokeFixtureIfRequested_uses_active_enterprise_host()
    {
        var databasePath = CreateArchiveDatabase();
        var previous = Environment.GetEnvironmentVariable(WindowsGitHubArchiveReader.SmokeArchiveFixtureEnvironmentVariable);
        try
        {
            Environment.SetEnvironmentVariable(WindowsGitHubArchiveReader.SmokeArchiveFixtureEnvironmentVariable, "1");
            WindowsGitHubArchiveReader.CreateSmokeFixtureIfRequested(new WindowsSettings
            {
                GitHubHost = "github.enterprise.test",
                GitHubArchiveDatabasePath = databasePath,
                Repositories = [new RepositoryRef { Owner = "owner", Name = "name" }],
            });

            var reader = new WindowsGitHubArchiveReader(databasePath, "github.enterprise.test");
            var repository = new RepositoryRef { Owner = "owner", Name = "name" };

            Assert.Contains(
                reader.RecentIssues(repository, limit: 5),
                issue => issue.Url == "https://github.enterprise.test/owner/name/issues/987");
            Assert.Contains(
                reader.RecentPulls(repository, limit: 5),
                pull => pull.Url == "https://github.enterprise.test/owner/name/pull/654");
        }
        finally
        {
            Environment.SetEnvironmentVariable(WindowsGitHubArchiveReader.SmokeArchiveFixtureEnvironmentVariable, previous);
            DeleteDatabase(databasePath);
        }
    }

    [Fact]
    public async Task Repository_client_uses_archive_lists_when_live_recent_lists_fail()
    {
        var databasePath = CreateArchiveDatabase();
        try
        {
            using (var connection = OpenWritable(databasePath))
            {
                CreateThreadsTable(connection);
                InsertThread(
                    connection,
                    repository: "owner/name",
                    kind: "issue",
                    number: 42,
                    title: "Archived issue",
                    state: "open",
                    updatedAt: "2026-06-01T12:00:00Z",
                    url: "https://github.com/owner/name/issues/42",
                    author: "alice");
                InsertThread(
                    connection,
                    repository: "owner/name",
                    kind: "pull",
                    number: 8,
                    title: "Archived pull",
                    state: "open",
                    updatedAt: "2026-06-01T13:00:00Z",
                    url: "https://github.com/owner/name/pull/8",
                    author: "bob");
            }

            var handler = new StubHandler(request =>
            {
                var path = request.RequestUri?.PathAndQuery ?? "";
                return path switch
                {
                    "/repos/owner/name" => JsonResponse("""
                        {
                          "open_issues_count": 2,
                          "stargazers_count": 10,
                          "forks_count": 2,
                          "default_branch": "main",
                          "pushed_at": "2026-06-01T00:00:00Z"
                        }
                        """),
                    "/repos/owner/name/pulls?state=open&per_page=1" => JsonResponse("[]"),
                    "/repos/owner/name/issues?state=open&sort=updated&direction=desc&per_page=10" => new HttpResponseMessage(HttpStatusCode.Forbidden),
                    "/repos/owner/name/pulls?state=all&sort=updated&direction=desc&per_page=5" => new HttpResponseMessage(HttpStatusCode.Forbidden),
                    "/repos/owner/name/actions/runs?branch=main&per_page=1" => JsonResponse("""{"workflow_runs":[]}"""),
                    "/repos/owner/name/actions/runs?per_page=5" => JsonResponse("""{"workflow_runs":[]}"""),
                    "/repos/owner/name/releases/latest" => new HttpResponseMessage(HttpStatusCode.NotFound),
                    "/repos/owner/name/contents/CHANGELOG.md?ref=main" => new HttpResponseMessage(HttpStatusCode.NotFound),
                    _ => JsonResponse("[]"),
                };
            });
            var graphQlHandler = new StubHandler(_ => JsonResponse("""
                {
                  "data": {
                    "repository": {
                      "discussions": {
                        "nodes": []
                      }
                    }
                  }
                }
                """));
            var settings = new WindowsSettings
            {
                EnableResponseCache = false,
                GitHubArchiveDatabasePath = databasePath,
            };
            using var client = new GitHubRepositoryClient(settings, token: null, handler, graphQlHandler, cache: null);

            var statuses = await client.LoadRepositoriesAsync(
                [new RepositoryRef { Owner = "owner", Name = "name" }],
                new LocalGitIndex([]),
                CancellationToken.None);

            var status = Assert.Single(statuses);
            Assert.Null(status.ErrorMessage);
            Assert.Contains(status.RecentLists.Issues, issue => issue.Title == "#42 Archived issue");
            Assert.Contains(status.RecentLists.Pulls, pull => pull.Title == "#8 Archived pull");
        }
        finally
        {
            DeleteDatabase(databasePath);
        }
    }

    [Fact]
    public async Task Repository_client_smoke_force_archive_fallback_uses_archive_recent_lists()
    {
        var databasePath = CreateArchiveDatabase();
        var previous = Environment.GetEnvironmentVariable(GitHubRepositoryClient.SmokeForceArchiveFallbackEnvironmentVariable);
        try
        {
            using (var connection = OpenWritable(databasePath))
            {
                CreateThreadsTable(connection);
                InsertThread(
                    connection,
                    repository: "owner/name",
                    kind: "issue",
                    number: 987,
                    title: "Smoke archive issue",
                    state: "open",
                    updatedAt: "2026-06-06T12:00:00Z",
                    url: "https://github.com/owner/name/issues/987",
                    author: "archive-issue-bot");
                InsertThread(
                    connection,
                    repository: "owner/name",
                    kind: "pull_request",
                    number: 654,
                    title: "Smoke archive pull",
                    state: "open",
                    updatedAt: "2026-06-06T12:01:00Z",
                    url: "https://github.com/owner/name/pull/654",
                    author: "archive-pr-bot");
            }

            Environment.SetEnvironmentVariable(GitHubRepositoryClient.SmokeForceArchiveFallbackEnvironmentVariable, "1");
            var handler = new StubHandler(request =>
            {
                var path = request.RequestUri?.PathAndQuery ?? "";
                return path switch
                {
                    "/repos/owner/name" => JsonResponse("""
                        {
                          "open_issues_count": 2,
                          "stargazers_count": 10,
                          "forks_count": 2,
                          "default_branch": "main",
                          "pushed_at": "2026-06-01T00:00:00Z"
                        }
                        """),
                    "/repos/owner/name/pulls?state=open&per_page=1" => JsonResponse("[]"),
                    "/repos/owner/name/issues?state=open&sort=updated&direction=desc&per_page=10" => JsonResponse("""
                        [
                          {
                            "number": 1,
                            "title": "Live issue should be bypassed",
                            "html_url": "https://github.com/owner/name/issues/1",
                            "updated_at": "2026-06-06T11:00:00Z",
                            "user": { "login": "live" }
                          }
                        ]
                        """),
                    "/repos/owner/name/pulls?state=all&sort=updated&direction=desc&per_page=5" => JsonResponse("""
                        [
                          {
                            "number": 2,
                            "title": "Live pull should be bypassed",
                            "html_url": "https://github.com/owner/name/pull/2",
                            "updated_at": "2026-06-06T11:00:00Z",
                            "user": { "login": "live" }
                          }
                        ]
                        """),
                    "/repos/owner/name/actions/runs?branch=main&per_page=1" => JsonResponse("""{"workflow_runs":[]}"""),
                    "/repos/owner/name/actions/runs?per_page=5" => JsonResponse("""{"workflow_runs":[]}"""),
                    "/repos/owner/name/releases/latest" => new HttpResponseMessage(HttpStatusCode.NotFound),
                    "/repos/owner/name/contents/CHANGELOG.md?ref=main" => new HttpResponseMessage(HttpStatusCode.NotFound),
                    _ => JsonResponse("[]"),
                };
            });
            var graphQlHandler = new StubHandler(_ => JsonResponse("""
                {
                  "data": {
                    "repository": {
                      "discussions": {
                        "nodes": []
                      }
                    }
                  }
                }
                """));
            var settings = new WindowsSettings
            {
                EnableResponseCache = false,
                GitHubArchiveDatabasePath = databasePath,
            };
            using var client = new GitHubRepositoryClient(settings, token: null, handler, graphQlHandler, cache: null);

            var statuses = await client.LoadRepositoriesAsync(
                [new RepositoryRef { Owner = "owner", Name = "name" }],
                new LocalGitIndex([]),
                CancellationToken.None);

            var status = Assert.Single(statuses);
            Assert.Contains(status.RecentLists.Issues, issue => issue.Title == "#987 Smoke archive issue");
            Assert.Contains(status.RecentLists.Pulls, pull => pull.Title == "#654 Smoke archive pull");
            Assert.DoesNotContain(status.RecentLists.Issues, issue => issue.Title.Contains("Live issue", StringComparison.Ordinal));
            Assert.DoesNotContain(status.RecentLists.Pulls, pull => pull.Title.Contains("Live pull", StringComparison.Ordinal));
        }
        finally
        {
            Environment.SetEnvironmentVariable(GitHubRepositoryClient.SmokeForceArchiveFallbackEnvironmentVariable, previous);
            DeleteDatabase(databasePath);
        }
    }

    private static string CreateArchiveDatabase()
    {
        var directory = Path.Combine(Path.GetTempPath(), $"repobar-archive-{Guid.NewGuid():N}");
        Directory.CreateDirectory(directory);
        return Path.Combine(directory, "archive.sqlite");
    }

    private static SqliteConnection OpenWritable(string databasePath)
    {
        var connection = new SqliteConnection($"Data Source={databasePath}");
        connection.Open();
        return connection;
    }

    private static void CreateThreadsTable(SqliteConnection connection)
    {
        using var command = connection.CreateCommand();
        command.CommandText = """
            create table threads(
                repository text not null,
                kind text not null,
                number text not null,
                title text,
                updated_at text,
                state text,
                html_url text,
                author_login text,
                _repobar_raw_json text not null
            )
            """;
        command.ExecuteNonQuery();
    }

    private static void InsertThread(
        SqliteConnection connection,
        string repository,
        string kind,
        int number,
        string title,
        string state,
        string updatedAt,
        string? url,
        string author)
    {
        using var command = connection.CreateCommand();
        command.CommandText = """
            insert into threads(
                repository, kind, number, title, updated_at, state, html_url, author_login, _repobar_raw_json
            ) values (
                $repository, $kind, $number, $title, $updated_at, $state, $html_url, $author_login, $raw_json
            )
            """;
        command.Parameters.AddWithValue("$repository", repository);
        command.Parameters.AddWithValue("$kind", kind);
        command.Parameters.AddWithValue("$number", number.ToString());
        command.Parameters.AddWithValue("$title", title);
        command.Parameters.AddWithValue("$updated_at", updatedAt);
        command.Parameters.AddWithValue("$state", state);
        command.Parameters.AddWithValue("$html_url", url is null ? DBNull.Value : url);
        command.Parameters.AddWithValue("$author_login", author);
        command.Parameters.AddWithValue(
            "$raw_json",
            JsonSerializer.Serialize(new
            {
                number,
                title,
                html_url = url,
                user = new { login = author },
            }));
        command.ExecuteNonQuery();
    }

    private static HttpResponseMessage JsonResponse(string json)
    {
        return new HttpResponseMessage(HttpStatusCode.OK)
        {
            Content = new StringContent(json, Encoding.UTF8, "application/json"),
        };
    }

    private static void DeleteDatabase(string databasePath)
    {
        var directory = Path.GetDirectoryName(databasePath);
        if (directory == null || !Directory.Exists(directory))
        {
            return;
        }

        SqliteConnection.ClearAllPools();
        for (var attempt = 0; attempt < 10; attempt++)
        {
            try
            {
                Directory.Delete(directory, recursive: true);
                return;
            }
            catch (IOException) when (attempt < 9)
            {
                Thread.Sleep(50);
            }
        }
    }

    private sealed class StubHandler : HttpMessageHandler
    {
        private readonly Func<HttpRequestMessage, HttpResponseMessage> _handler;

        public StubHandler(Func<HttpRequestMessage, HttpResponseMessage> handler)
        {
            _handler = handler;
        }

        protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken cancellationToken)
        {
            return Task.FromResult(_handler(request));
        }
    }
}
