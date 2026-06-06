using System.Runtime.InteropServices;
using System.Text;

namespace RepoBar.Windows;

internal sealed class WindowsCredentialStore
{
    private const int CredTypeGeneric = 1;
    private const int CredPersistLocalMachine = 2;
    private const string TargetPrefix = "RepoBar.Windows";
    private const string OAuthTargetPrefix = "RepoBar.Windows.OAuth";

    public string TargetName { get; }

    public WindowsCredentialStore(string gitHubHost)
        : this(BuildTargetName(gitHubHost), TargetNameMode.AlreadyBuilt)
    {
    }

    private WindowsCredentialStore(string targetName, TargetNameMode _)
    {
        TargetName = targetName;
    }

    public static string BuildTargetName(string gitHubHost)
    {
        return BuildTargetName(gitHubHost, TargetPrefix);
    }

    public static string BuildOAuthTargetName(string gitHubHost)
    {
        return BuildTargetName(gitHubHost, OAuthTargetPrefix);
    }

    public static WindowsCredentialStore CreateOAuthStore(string gitHubHost)
    {
        return new WindowsCredentialStore(BuildOAuthTargetName(gitHubHost), TargetNameMode.AlreadyBuilt);
    }

    private enum TargetNameMode
    {
        AlreadyBuilt,
    }

    private static string BuildTargetName(string gitHubHost, string prefix)
    {
        var host = GitHubHost.Normalize(gitHubHost);
        var safeHost = string.Concat(host.Select(character =>
            char.IsAsciiLetterOrDigit(character) || character is '.' or '-' ? character : '-'));
        return $"{prefix}:{safeHost}";
    }

    public bool HasToken()
    {
        return ReadToken() != null;
    }

    public string? ReadToken()
    {
        if (!OperatingSystem.IsWindows())
        {
            return null;
        }

        if (!CredRead(TargetName, CredTypeGeneric, 0, out var credentialPointer))
        {
            return null;
        }

        try
        {
            var credential = Marshal.PtrToStructure<CredentialNative>(credentialPointer);
            if (credential.CredentialBlob == IntPtr.Zero || credential.CredentialBlobSize == 0)
            {
                return null;
            }

            var bytes = new byte[credential.CredentialBlobSize];
            Marshal.Copy(credential.CredentialBlob, bytes, 0, bytes.Length);
            return Encoding.Unicode.GetString(bytes);
        }
        finally
        {
            CredFree(credentialPointer);
        }
    }

    public void SaveToken(string token)
    {
        if (!OperatingSystem.IsWindows())
        {
            throw new PlatformNotSupportedException("Windows Credential Manager is only available on Windows.");
        }
        if (string.IsNullOrWhiteSpace(token))
        {
            return;
        }

        var bytes = Encoding.Unicode.GetBytes(token.Trim());
        var blob = Marshal.AllocCoTaskMem(bytes.Length);
        try
        {
            Marshal.Copy(bytes, 0, blob, bytes.Length);
            var credential = new CredentialNative
            {
                Type = CredTypeGeneric,
                TargetName = TargetName,
                CredentialBlobSize = bytes.Length,
                CredentialBlob = blob,
                Persist = CredPersistLocalMachine,
                UserName = "RepoBar",
            };

            if (!CredWrite(ref credential, 0))
            {
                throw new InvalidOperationException($"Credential Manager write failed: {Marshal.GetLastWin32Error()}");
            }
        }
        finally
        {
            Marshal.FreeCoTaskMem(blob);
        }
    }

    public void ClearToken()
    {
        if (!OperatingSystem.IsWindows())
        {
            return;
        }

        _ = CredDelete(TargetName, CredTypeGeneric, 0);
    }

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    private struct CredentialNative
    {
        public int Flags;
        public int Type;
        public string TargetName;
        public string? Comment;
        public long LastWritten;
        public int CredentialBlobSize;
        public IntPtr CredentialBlob;
        public int Persist;
        public int AttributeCount;
        public IntPtr Attributes;
        public string? TargetAlias;
        public string? UserName;
    }

    [DllImport("Advapi32.dll", EntryPoint = "CredReadW", SetLastError = true, CharSet = CharSet.Unicode)]
    private static extern bool CredRead(string target, int type, int reservedFlag, out IntPtr credentialPointer);

    [DllImport("Advapi32.dll", EntryPoint = "CredWriteW", SetLastError = true, CharSet = CharSet.Unicode)]
    private static extern bool CredWrite(ref CredentialNative userCredential, uint flags);

    [DllImport("Advapi32.dll", EntryPoint = "CredDeleteW", SetLastError = true, CharSet = CharSet.Unicode)]
    private static extern bool CredDelete(string target, int type, int flags);

    [DllImport("Advapi32.dll", SetLastError = true)]
    private static extern void CredFree(IntPtr buffer);
}
