using System.Globalization;
using System.Text.Json;
using Microsoft.Data.Sqlite;

namespace RepoBar.Windows;

internal sealed class WindowsGitHubArchiveReader
{
    internal const string SmokeArchiveFixtureEnvironmentVariable = "REPOBAR_WINDOWS_SMOKE_ARCHIVE_FIXTURE";

    private readonly string _databasePath;
    private readonly string _gitHubHost;

    public WindowsGitHubArchiveReader(string databasePath)
        : this(databasePath, "github.com")
    {
    }

    internal WindowsGitHubArchiveReader(string databasePath, string gitHubHost)
    {
        _databasePath = ResolvePath(databasePath);
        _gitHubHost = GitHubHost.Normalize(gitHubHost);
    }

    public static WindowsGitHubArchiveReader? FromSettings(WindowsSettings settings)
    {
        return string.IsNullOrWhiteSpace(settings.GitHubArchiveDatabasePath)
            ? null
            : new WindowsGitHubArchiveReader(settings.GitHubArchiveDatabasePath, settings.GitHubHost);
    }

    internal static void CreateSmokeFixtureIfRequested(WindowsSettings settings)
    {
        if (!string.Equals(
            Environment.GetEnvironmentVariable(SmokeArchiveFixtureEnvironmentVariable),
            "1",
            StringComparison.Ordinal) ||
            string.IsNullOrWhiteSpace(settings.GitHubArchiveDatabasePath))
        {
            return;
        }

        var databasePath = ResolvePath(settings.GitHubArchiveDatabasePath);
        var directory = Path.GetDirectoryName(databasePath);
        if (!string.IsNullOrWhiteSpace(directory))
        {
            Directory.CreateDirectory(directory);
        }
        if (File.Exists(databasePath))
        {
            File.Delete(databasePath);
        }

        using var connection = new SqliteConnection($"Data Source={databasePath}");
        connection.Open();
        using (var command = connection.CreateCommand())
        {
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

        InsertSmokeThread(
            connection,
            settings.GitHubHost,
            settings.GetActiveRepositories().FirstOrDefault(repository => repository.IsValid) ??
                new RepositoryRef { Owner = "steipete", Name = "RepoBar" },
            kind: "issue",
            number: 987,
            title: "Smoke archive issue",
            urlKind: "issues",
            author: "archive-issue-bot");
        InsertSmokeThread(
            connection,
            settings.GitHubHost,
            settings.GetActiveRepositories().FirstOrDefault(repository => repository.IsValid) ??
                new RepositoryRef { Owner = "steipete", Name = "RepoBar" },
            kind: "pull_request",
            number: 654,
            title: "Smoke archive pull",
            urlKind: "pull",
            author: "archive-pr-bot");
    }

    public IReadOnlyList<GitHubListItem> RecentIssues(RepositoryRef repository, int limit)
    {
        return ReadThreads(repository, ["issue"], Math.Max(0, limit), "issues")
            .Select(row => row.ToListItem())
            .ToArray();
    }

    public IReadOnlyList<GitHubListItem> RecentPulls(RepositoryRef repository, int limit)
    {
        return ReadThreads(repository, ["pull", "pr", "pull_request"], Math.Max(0, limit), "pull")
            .Select(row => row.ToListItem())
            .ToArray();
    }

    private IReadOnlyList<ArchiveThreadRow> ReadThreads(
        RepositoryRef repository,
        IReadOnlyList<string> kinds,
        int limit,
        string fallbackUrlKind)
    {
        if (limit <= 0 || !File.Exists(_databasePath))
        {
            return [];
        }

        try
        {
            var connectionString = new SqliteConnectionStringBuilder
            {
                DataSource = _databasePath,
                Mode = SqliteOpenMode.ReadOnly,
            }.ToString();
            using var connection = new SqliteConnection(connectionString);
            connection.Open();
            if (!TableExists(connection, "threads"))
            {
                return [];
            }

            var columns = ColumnSet(connection, "threads");
            if (!columns.Contains("repository") || !columns.Contains("kind") || !columns.Contains("number"))
            {
                return [];
            }

            var selection = new ThreadColumnSelection(columns);
            var kindParameters = string.Join(", ", kinds.Select((_, index) => $"$kind{index}"));
            var statePredicate = columns.Contains("state")
                ? "and lower(coalesce(\"state\", 'open')) = 'open'"
                : "";
            using var command = connection.CreateCommand();
            command.CommandText = $"""
                select {selection.Sql}
                from "threads"
                where lower("repository") = $repository
                  and lower("kind") in ({kindParameters})
                  {statePredicate}
                order by {selection.UpdatedAtOrderSql} desc, cast("number" as integer) desc
                limit $limit
                """;
            command.Parameters.AddWithValue("$repository", repository.FullName.ToLowerInvariant());
            for (var index = 0; index < kinds.Count; index++)
            {
                command.Parameters.AddWithValue($"$kind{index}", kinds[index]);
            }

            command.Parameters.AddWithValue("$limit", limit);
            using var reader = command.ExecuteReader();
            var rows = new List<ArchiveThreadRow>();
            while (reader.Read())
            {
                try
                {
                    if (TryReadThread(reader, repository, fallbackUrlKind) is { } row)
                    {
                        rows.Add(row);
                    }
                }
                catch (JsonException)
                {
                    // Skip corrupt rows in otherwise readable archive databases.
                }
            }

            return rows;
        }
        catch (SqliteException)
        {
            return [];
        }
        catch (InvalidOperationException)
        {
            return [];
        }
    }

    private ArchiveThreadRow? TryReadThread(SqliteDataReader reader, RepositoryRef repository, string fallbackUrlKind)
    {
        using var rawDocument = ParseRawJson(ReadString(reader, "raw_json"));
        var raw = rawDocument?.RootElement;
        var number = ReadInt(reader, "number") ?? JsonInt(raw, "number");
        if (number == null)
        {
            return null;
        }

        var title = ReadString(reader, "title") ?? JsonString(raw, "title") ?? $"#{number.Value}";
        var updatedAt = ParseDate(ReadString(reader, "updated_at"))
            ?? ParseDate(JsonString(raw, "updated_at", "updatedAt"));
        var url = ReadString(reader, "url")
            ?? ReadString(reader, "html_url")
            ?? JsonString(raw, "html_url", "htmlUrl", "url")
            ?? ThreadUrl(_gitHubHost, repository, fallbackUrlKind, number.Value);
        var author = ReadString(reader, "author_login")
            ?? JsonString(raw, "author_login")
            ?? JsonNestedString(raw, "user", "login")
            ?? JsonNestedString(raw, "author", "login");

        return new ArchiveThreadRow(number.Value, title, url, author, updatedAt);
    }

    private static bool TableExists(SqliteConnection connection, string tableName)
    {
        using var command = connection.CreateCommand();
        command.CommandText = "select exists(select 1 from sqlite_master where type = 'table' and name = $name)";
        command.Parameters.AddWithValue("$name", tableName);
        return Convert.ToInt32(command.ExecuteScalar(), CultureInfo.InvariantCulture) == 1;
    }

    private static HashSet<string> ColumnSet(SqliteConnection connection, string tableName)
    {
        using var command = connection.CreateCommand();
        command.CommandText = $"pragma table_info({Quoted(tableName)})";
        using var reader = command.ExecuteReader();
        var columns = new HashSet<string>(StringComparer.Ordinal);
        while (reader.Read())
        {
            var name = reader["name"] as string;
            if (!string.IsNullOrWhiteSpace(name))
            {
                columns.Add(name);
            }
        }

        return columns;
    }

    private static JsonDocument? ParseRawJson(string? value)
    {
        if (string.IsNullOrWhiteSpace(value))
        {
            return null;
        }

        var document = JsonDocument.Parse(value);
        return document.RootElement.ValueKind == JsonValueKind.Object ? document : null;
    }

    private static string? ReadString(SqliteDataReader reader, string alias)
    {
        var ordinal = reader.GetOrdinal(alias);
        return reader.IsDBNull(ordinal) ? null : Convert.ToString(reader.GetValue(ordinal), CultureInfo.InvariantCulture);
    }

    private static int? ReadInt(SqliteDataReader reader, string alias)
    {
        var value = ReadString(reader, alias);
        return int.TryParse(value, NumberStyles.Integer, CultureInfo.InvariantCulture, out var number) ? number : null;
    }

    private static int? JsonInt(JsonElement? raw, params string[] names)
    {
        if (raw == null || raw.Value.ValueKind != JsonValueKind.Object)
        {
            return null;
        }

        var element = raw.Value;
        foreach (var name in names)
        {
            if (!element.TryGetProperty(name, out var property))
            {
                continue;
            }

            if (property.ValueKind == JsonValueKind.Number && property.TryGetInt32(out var number))
            {
                return number;
            }

            if (property.ValueKind == JsonValueKind.String &&
                int.TryParse(property.GetString(), NumberStyles.Integer, CultureInfo.InvariantCulture, out number))
            {
                return number;
            }
        }

        return null;
    }

    private static string? JsonString(JsonElement? raw, params string[] names)
    {
        if (raw == null || raw.Value.ValueKind != JsonValueKind.Object)
        {
            return null;
        }

        var element = raw.Value;
        foreach (var name in names)
        {
            if (!element.TryGetProperty(name, out var property))
            {
                continue;
            }

            if (property.ValueKind == JsonValueKind.String)
            {
                var value = property.GetString()?.Trim();
                if (!string.IsNullOrWhiteSpace(value))
                {
                    return value;
                }
            }
            else if (property.ValueKind == JsonValueKind.Number)
            {
                return property.ToString();
            }
        }

        return null;
    }

    private static string? JsonNestedString(JsonElement? raw, string objectName, string propertyName)
    {
        if (raw == null ||
            raw.Value.ValueKind != JsonValueKind.Object ||
            !raw.Value.TryGetProperty(objectName, out var nested) ||
            nested.ValueKind != JsonValueKind.Object)
        {
            return null;
        }

        return JsonString(nested, propertyName);
    }

    private static DateTimeOffset? ParseDate(string? value)
    {
        return DateTimeOffset.TryParse(value, CultureInfo.InvariantCulture, DateTimeStyles.AssumeUniversal, out var date)
            ? date
            : null;
    }

    private static string? Metadata(string? actor, DateTimeOffset? date)
    {
        var parts = new List<string>();
        if (!string.IsNullOrWhiteSpace(actor))
        {
            parts.Add(actor);
        }

        if (date != null)
        {
            parts.Add(date.Value.LocalDateTime.ToString("g", CultureInfo.CurrentCulture));
        }

        return parts.Count == 0 ? null : string.Join(" - ", parts);
    }

    private static void InsertSmokeThread(
        SqliteConnection connection,
        string gitHubHost,
        RepositoryRef repository,
        string kind,
        int number,
        string title,
        string urlKind,
        string author)
    {
        var url = ThreadUrl(gitHubHost, repository, urlKind, number);
        using var command = connection.CreateCommand();
        command.CommandText = """
            insert into threads(
                repository, kind, number, title, updated_at, state, html_url, author_login, _repobar_raw_json
            ) values (
                $repository, $kind, $number, $title, $updated_at, $state, $html_url, $author_login, $raw_json
            )
            """;
        command.Parameters.AddWithValue("$repository", repository.FullName);
        command.Parameters.AddWithValue("$kind", kind);
        command.Parameters.AddWithValue("$number", number.ToString(CultureInfo.InvariantCulture));
        command.Parameters.AddWithValue("$title", title);
        command.Parameters.AddWithValue("$updated_at", DateTimeOffset.UtcNow.ToString("o", CultureInfo.InvariantCulture));
        command.Parameters.AddWithValue("$state", "open");
        command.Parameters.AddWithValue("$html_url", url);
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

    private static string ThreadUrl(string gitHubHost, RepositoryRef repository, string urlKind, int number)
    {
        return $"https://{GitHubHost.Normalize(gitHubHost)}/{repository.Owner}/{repository.Name}/{urlKind}/{number}";
    }

    private static string ResolvePath(string path)
    {
        var expanded = Environment.ExpandEnvironmentVariables(path.Trim());
        if (expanded == "~")
        {
            return Environment.GetFolderPath(Environment.SpecialFolder.UserProfile);
        }

        if (expanded.StartsWith("~/", StringComparison.Ordinal) || expanded.StartsWith(@"~\", StringComparison.Ordinal))
        {
            return Path.Combine(
                Environment.GetFolderPath(Environment.SpecialFolder.UserProfile),
                expanded[2..]);
        }

        return expanded;
    }

    private static string Quoted(string identifier)
    {
        return $"\"{identifier.Replace("\"", "\"\"", StringComparison.Ordinal)}\"";
    }

    private sealed record ThreadColumnSelection(string Sql, string UpdatedAtOrderSql)
    {
        public ThreadColumnSelection(HashSet<string> columns)
            : this(
                string.Join(", ", AliasMap.Select(alias => SelectExpression(columns, alias.Alias, alias.Candidates))),
                columns.Contains("updated_at") ? "\"updated_at\"" : columns.Contains("updatedAt") ? "\"updatedAt\"" : "\"number\"")
        {
        }

        private static readonly (string Alias, string[] Candidates)[] AliasMap =
        [
            ("number", ["number"]),
            ("title", ["title"]),
            ("updated_at", ["updated_at", "updatedAt"]),
            ("url", ["url"]),
            ("html_url", ["html_url", "htmlUrl"]),
            ("author_login", ["author_login", "author"]),
            ("raw_json", ["_repobar_raw_json", "raw_json"]),
        ];

        private static string SelectExpression(HashSet<string> columns, string alias, IReadOnlyList<string> candidates)
        {
            var column = candidates.FirstOrDefault(columns.Contains);
            return column == null
                ? $"null as {Quoted(alias)}"
                : $"{Quoted(column)} as {Quoted(alias)}";
        }
    }

    private sealed record ArchiveThreadRow(int Number, string Title, string? Url, string? Author, DateTimeOffset? UpdatedAt)
    {
        public GitHubListItem ToListItem()
        {
            return new GitHubListItem($"#{Number} {Title}", Url, Metadata(Author, UpdatedAt), AuthorLogin: Author);
        }
    }
}
