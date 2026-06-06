namespace RepoBar.Windows;

internal static class WindowsRepositoryOwnerFilter
{
    public static bool IsOnlyViewer(IReadOnlyList<string> owners, string? viewerLogin)
    {
        return !string.IsNullOrWhiteSpace(viewerLogin) &&
            owners.Count == 1 &&
            string.Equals(owners[0], viewerLogin.Trim(), StringComparison.OrdinalIgnoreCase);
    }

    public static IReadOnlyList<string> ToggleOnlyViewer(IReadOnlyList<string> owners, string viewerLogin)
    {
        return IsOnlyViewer(owners, viewerLogin)
            ? []
            : [viewerLogin.Trim()];
    }
}
