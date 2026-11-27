using System.Diagnostics;
using System.Globalization;
using System.Runtime.InteropServices;
using System.Text;
using System.Text.Json;
using MediaBrowser.Controller.MediaEncoding;
using Microsoft.Extensions.Logging;

namespace Jellyfin.Plugin.PoyrazTema;

public record Candidate(string Id, string Title, double Duration, long Views, string Channel)
{
    public string Url => $"https://www.youtube.com/watch?v={Id}";
}

/// <summary>yt-dlp ile YouTube'da arar, en uygun sonucu seçer, theme.mp3 olarak indirir.</summary>
public class ThemeFinder
{
    private static readonly string[] Good = { "theme", "main title", "opening", "intro", "jenerik", "soundtrack", "ost", "score", "music", "müzi" };
    private static readonly string[] Bad =
    {
        "trailer", "fragman", "teaser", "review", "reaction", "explained", "full movie", "full film", "scene", "behind the",
        "interview", "cover", "piano", "guitar", "violin", "remix", "1 hour", "10 hour", "hours", "extended", "karaoke",
        "tiktok", "#shorts", "analysis", "fan made", "fanmade", "parody", "8-bit", "8 bit", "lofi", "lo-fi", "slowed", "reverb",
        "nightcore", "tutorial", "how to", "compilation", "every", "ranking", "top 10",
    };

    private readonly ILogger<ThemeFinder> _log;
    private readonly IHttpClientFactory _http;
    private readonly IMediaEncoder _encoder;
    private readonly SemaphoreSlim _toolLock = new(1, 1);

    public ThemeFinder(ILogger<ThemeFinder> log, IHttpClientFactory http, IMediaEncoder encoder)
    {
        _log = log;
        _http = http;
        _encoder = encoder;
    }

    private static string ToolPath => Path.Combine(
        Plugin.Instance!.DataFolderPath,
        "bin",
        RuntimeInformation.IsOSPlatform(OSPlatform.Windows) ? "yt-dlp.exe" : "yt-dlp");

    /// <summary>yt-dlp'yi eklentinin klasörüne indirir; haftada bir yeniler (YouTube değiştikçe güncellenmesi gerekir).</summary>
    public async Task<string> EnsureToolAsync(CancellationToken ct)
    {
        await _toolLock.WaitAsync(ct).ConfigureAwait(false);
        try
        {
            var p = ToolPath;
            if (File.Exists(p) && DateTime.UtcNow - File.GetLastWriteTimeUtc(p) < TimeSpan.FromDays(7))
            {
                return p;
            }

            string asset;
            if (RuntimeInformation.IsOSPlatform(OSPlatform.Windows))
            {
                asset = "yt-dlp.exe";
            }
            else if (RuntimeInformation.IsOSPlatform(OSPlatform.OSX))
            {
                asset = "yt-dlp_macos";
            }
            else
            {
                asset = RuntimeInformation.OSArchitecture == Architecture.Arm64 ? "yt-dlp_linux_aarch64" : "yt-dlp_linux";
            }

            try
            {
                Directory.CreateDirectory(Path.GetDirectoryName(p)!);
                using var client = _http.CreateClient();
                client.Timeout = TimeSpan.FromMinutes(3);
                var bytes = await client.GetByteArrayAsync($"https://github.com/yt-dlp/yt-dlp/releases/latest/download/{asset}", ct).ConfigureAwait(false);
                var tmp = p + ".new";
                await File.WriteAllBytesAsync(tmp, bytes, ct).ConfigureAwait(false);
                if (!RuntimeInformation.IsOSPlatform(OSPlatform.Windows))
                {
                    File.SetUnixFileMode(tmp, UnixFileMode.UserRead | UnixFileMode.UserWrite | UnixFileMode.UserExecute | UnixFileMode.GroupRead | UnixFileMode.GroupExecute | UnixFileMode.OtherRead | UnixFileMode.OtherExecute);
                }

                File.Move(tmp, p, true);
                _log.LogInformation("Poyraz Tema: yt-dlp indirildi ({Asset})", asset);
            }
            catch (Exception e) when (File.Exists(p))
            {
                _log.LogWarning(e, "Poyraz Tema: yt-dlp güncellenemedi, eldeki sürüm kullanılacak");
            }

            return p;
        }
        finally
        {
            _toolLock.Release();
        }
    }

    private async Task<(int Code, string Out, string Err)> RunAsync(IEnumerable<string> args, TimeSpan timeout, CancellationToken ct)
    {
        var tool = await EnsureToolAsync(ct).ConfigureAwait(false);
        var psi = new ProcessStartInfo(tool)
        {
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            UseShellExecute = false,
            CreateNoWindow = true,
            StandardOutputEncoding = Encoding.UTF8,
            StandardErrorEncoding = Encoding.UTF8,
        };
        foreach (var a in args)
        {
            psi.ArgumentList.Add(a);
        }

        using var proc = Process.Start(psi) ?? throw new InvalidOperationException("yt-dlp başlatılamadı");
        using var cts = CancellationTokenSource.CreateLinkedTokenSource(ct);
        cts.CancelAfter(timeout);
        var outTask = proc.StandardOutput.ReadToEndAsync(cts.Token);
        var errTask = proc.StandardError.ReadToEndAsync(cts.Token);
        try
        {
            await proc.WaitForExitAsync(cts.Token).ConfigureAwait(false);
        }
        catch (OperationCanceledException)
        {
            try
            {
                proc.Kill(true);
            }
            catch
            {
                // zaten kapanmış
            }

            throw;
        }

        return (proc.ExitCode, await outTask.ConfigureAwait(false), await errTask.ConfigureAwait(false));
    }

    public async Task<List<Candidate>> SearchAsync(string query, int n, CancellationToken ct)
    {
        var (code, output, err) = await RunAsync(
            new[] { $"ytsearch{n}:{query}", "--dump-json", "--flat-playlist", "--no-warnings", "--skip-download" },
            TimeSpan.FromMinutes(2),
            ct).ConfigureAwait(false);
        if (code != 0 && string.IsNullOrWhiteSpace(output))
        {
            throw new InvalidOperationException(err.Trim().Split('\n').LastOrDefault() ?? "yt-dlp hatası");
        }

        var list = new List<Candidate>();
        foreach (var line in output.Split('\n', StringSplitOptions.RemoveEmptyEntries))
        {
            try
            {
                using var doc = JsonDocument.Parse(line);
                var r = doc.RootElement;
                var id = r.TryGetProperty("id", out var i) ? i.GetString() : null;
                if (string.IsNullOrEmpty(id))
                {
                    continue;
                }

                list.Add(new Candidate(
                    id,
                    r.TryGetProperty("title", out var t) ? t.GetString() ?? string.Empty : string.Empty,
                    r.TryGetProperty("duration", out var d) && d.ValueKind == JsonValueKind.Number ? d.GetDouble() : 0,
                    r.TryGetProperty("view_count", out var v) && v.ValueKind == JsonValueKind.Number ? v.GetInt64() : 0,
                    r.TryGetProperty("channel", out var c) ? c.GetString() ?? string.Empty : string.Empty));
            }
            catch (JsonException)
            {
                // bozuk satır: atla
            }
        }

        return list;
    }

    public static string Norm(string s)
    {
        var lower = s.ToLower(new CultureInfo("tr-TR"));
        var sb = new StringBuilder();
        foreach (var ch in lower)
        {
            sb.Append(char.IsLetterOrDigit(ch) ? ch : ' ');
        }

        return " " + string.Join(' ', sb.ToString().Split(' ', StringSplitOptions.RemoveEmptyEntries)) + " ";
    }

    /// <summary>0–100 arası uygunluk; süre aralık dışındaysa -1.</summary>
    public static double Score(Candidate c, IEnumerable<string> names, int? year, int minSec, int maxSec)
    {
        if (c.Duration > 0 && (c.Duration < minSec || c.Duration > maxSec))
        {
            return -1;
        }

        var t = Norm(c.Title);
        double best = 0;
        foreach (var n in names)
        {
            var tokens = Norm(n).Split(' ', StringSplitOptions.RemoveEmptyEntries).Where(x => x.Length > 1).ToList();
            if (tokens.Count == 0)
            {
                continue;
            }

            var hit = tokens.Count(x => t.Contains(" " + x + " ", StringComparison.Ordinal));
            best = Math.Max(best, (double)hit / tokens.Count);
        }

        if (best < 0.5)
        {
            return 0; // başlık yapımın adını içermiyorsa alma
        }

        double s = best * 50;
        if (Good.Any(g => t.Contains(g, StringComparison.Ordinal)))
        {
            s += 20;
        }

        s -= Bad.Count(b => t.Contains(Norm(b).Trim(), StringComparison.Ordinal)) * 40;
        if (year.HasValue && t.Contains(year.Value.ToString(CultureInfo.InvariantCulture), StringComparison.Ordinal))
        {
            s += 5;
        }

        if (c.Duration >= 45 && c.Duration <= 240)
        {
            s += 8;
        }

        s += Math.Min(17, Math.Log10(c.Views + 1) * 2.5);
        return Math.Max(0, s);
    }

    /// <summary>URL'deki sesi klasöre theme.mp3 olarak indirir.</summary>
    public async Task DownloadAsync(string url, string dir, CancellationToken ct)
    {
        var target = Path.Combine(dir, "theme.mp3");
        var ffmpegDir = Path.GetDirectoryName(_encoder.EncoderPath) ?? string.Empty;
        var args = new List<string>
        {
            url, "-x", "--audio-format", "mp3", "--audio-quality", "4", "--no-playlist", "--no-warnings",
            "-o", Path.Combine(dir, "theme.%(ext)s"),
        };
        if (!string.IsNullOrEmpty(ffmpegDir))
        {
            args.Add("--ffmpeg-location");
            args.Add(ffmpegDir);
        }

        var (code, _, err) = await RunAsync(args, TimeSpan.FromMinutes(5), ct).ConfigureAwait(false);
        if (code != 0 || !File.Exists(target))
        {
            var last = err.Trim().Split('\n').LastOrDefault() ?? string.Empty;
            if (last.Contains("Permission denied", StringComparison.OrdinalIgnoreCase) || last.Contains("Read-only", StringComparison.OrdinalIgnoreCase))
            {
                throw new InvalidOperationException("Klasöre yazılamıyor (medya klasörü salt okunur bağlanmış olabilir).");
            }

            throw new InvalidOperationException(string.IsNullOrEmpty(last) ? "İndirilemedi." : last);
        }
    }
}
