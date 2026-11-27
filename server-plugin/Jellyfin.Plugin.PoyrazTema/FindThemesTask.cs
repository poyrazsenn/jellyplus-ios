using Jellyfin.Data.Enums;
using MediaBrowser.Controller.Entities;
using MediaBrowser.Controller.Library;
using MediaBrowser.Model.Tasks;
using Microsoft.Extensions.Logging;

namespace Jellyfin.Plugin.PoyrazTema;

/// <summary>Pano → Zamanlanmış Görevler: "Eksik tema müziklerini bul" (her gece 03:00).</summary>
public class FindThemesTask : IScheduledTask
{
    private static readonly string[] VideoExt = { ".mkv", ".mp4", ".m4v", ".avi", ".mov", ".ts", ".webm", ".wmv", ".mpg", ".mpeg", ".iso" };

    private readonly ILibraryManager _library;
    private readonly ThemeFinder _finder;
    private readonly ILogger<FindThemesTask> _log;

    public FindThemesTask(ILibraryManager library, ThemeFinder finder, ILogger<FindThemesTask> log)
    {
        _library = library;
        _finder = finder;
        _log = log;
    }

    public string Name => "Eksik tema müziklerini bul";

    public string Key => "PoyrazTemaFind";

    public string Description => "Tema müziği olmayan film ve dizileri YouTube'da arar ve theme.mp3 olarak indirir.";

    public string Category => "Poyraz Tema";

    public IEnumerable<TaskTriggerInfo> GetDefaultTriggers()
    {
        return new[]
        {
            new TaskTriggerInfo { Type = TaskTriggerInfoType.DailyTrigger, TimeOfDayTicks = TimeSpan.FromHours(3).Ticks },
        };
    }

    /// <summary>Tema müziğinin konacağı klasör; film kendi klasöründe değilse null (yanlış filme müzik gitmesin).</summary>
    public static string? FolderFor(BaseItem item, out string? why)
    {
        why = null;
        if (item is MediaBrowser.Controller.Entities.TV.Series)
        {
            return Directory.Exists(item.Path) ? item.Path : null;
        }

        var dir = item.ContainingFolderPath;
        if (string.IsNullOrEmpty(dir) || !Directory.Exists(dir))
        {
            return null;
        }

        var videos = Directory.EnumerateFiles(dir).Count(f => VideoExt.Contains(Path.GetExtension(f).ToLowerInvariant()));
        if (videos > 2)
        {
            why = "Film kendi klasöründe değil; tema müziği bütün filmlere uygulanırdı.";
            return null;
        }

        return dir;
    }

    /// <summary>Tema müziği olmayan ve henüz bulunmamış yapımlar (sırada bekleyenler).</summary>
    public static List<BaseItem> Missing(ILibraryManager library, Configuration.PluginConfiguration cfg)
    {
        var kinds = new List<BaseItemKind>();
        if (cfg.Movies)
        {
            kinds.Add(BaseItemKind.Movie);
        }

        if (cfg.Series)
        {
            kinds.Add(BaseItemKind.Series);
        }

        if (kinds.Count == 0)
        {
            return new();
        }

        return library.GetItemList(new InternalItemsQuery { IncludeItemTypes = kinds.ToArray(), IsVirtualItem = false, Recursive = true })
            .Where(i =>
            {
                var d = FolderFor(i, out _);
                return d != null && !HasTheme(d);
            })
            .ToList();
    }

    public static bool HasTheme(string dir) =>
        File.Exists(Path.Combine(dir, "theme.mp3"))
        || File.Exists(Path.Combine(dir, "theme.m4a"))
        || File.Exists(Path.Combine(dir, "theme.flac"))
        || (Directory.Exists(Path.Combine(dir, "theme-music")) && Directory.EnumerateFiles(Path.Combine(dir, "theme-music")).Any());

    public async Task ExecuteAsync(IProgress<double> progress, CancellationToken cancellationToken)
    {
        var cfg = Plugin.Instance!.Configuration;
        var kinds = new List<BaseItemKind>();
        if (cfg.Movies)
        {
            kinds.Add(BaseItemKind.Movie);
        }

        if (cfg.Series)
        {
            kinds.Add(BaseItemKind.Series);
        }

        if (kinds.Count == 0)
        {
            return;
        }

        await _finder.EnsureToolAsync(cancellationToken).ConfigureAwait(false);

        var items = _library.GetItemList(new InternalItemsQuery
        {
            IncludeItemTypes = kinds.ToArray(),
            IsVirtualItem = false,
            Recursive = true,
        });

        var store = ThemeStore.Load();
        var todo = new List<(BaseItem Item, string Dir)>();
        foreach (var item in items)
        {
            var key = item.Id.ToString("N");
            var dir = FolderFor(item, out var why);
            if (dir == null)
            {
                if (why != null && !store.ContainsKey(key))
                {
                    ThemeStore.Put(Rec(item, "skipped", null, null, why));
                }

                continue;
            }

            if (HasTheme(dir))
            {
                continue;
            }

            if (store.TryGetValue(key, out var r) && (r.Status is "notfound" or "error")
                && DateTime.UtcNow - r.When < TimeSpan.FromDays(Math.Max(1, cfg.RetryDays)))
            {
                continue;
            }

            todo.Add((item, dir));
        }

        // En son eklenenler önce: yeni filmler ertesi sabah müzikli olsun
        todo = todo.OrderByDescending(t => t.Item.DateCreated).Take(Math.Max(1, cfg.MaxPerRun)).ToList();
        _log.LogInformation("Poyraz Tema: {Count} yapım için tema aranacak", todo.Count);
        var got = 0;
        for (var i = 0; i < todo.Count; i++)
        {
            cancellationToken.ThrowIfCancellationRequested();
            var (item, dir) = todo[i];
            try
            {
                var best = await FindBestAsync(_finder, item, cfg, cancellationToken).ConfigureAwait(false);
                if (best == null)
                {
                    ThemeStore.Put(Rec(item, "notfound", null, null, "Uygun sonuç bulunamadı."));
                }
                else
                {
                    await _finder.DownloadAsync(best.Url, dir, cancellationToken).ConfigureAwait(false);
                    ThemeStore.Put(Rec(item, "found", best.Url, best.Title, null));
                    got++;
                    _log.LogInformation("Poyraz Tema: {Name} → {Title}", item.Name, best.Title);
                }
            }
            catch (OperationCanceledException)
            {
                throw;
            }
            catch (Exception e)
            {
                _log.LogWarning(e, "Poyraz Tema: {Name} için tema alınamadı", item.Name);
                ThemeStore.Put(Rec(item, "error", null, null, e.Message));
            }

            progress.Report((i + 1) * 100.0 / todo.Count);
            await Task.Delay(TimeSpan.FromSeconds(2), cancellationToken).ConfigureAwait(false);
        }

        if (got > 0)
        {
            _library.QueueLibraryScan();
        }
    }

    public static async Task<Candidate?> FindBestAsync(ThemeFinder finder, BaseItem item, Configuration.PluginConfiguration cfg, CancellationToken ct)
    {
        var names = new List<string> { item.Name };
        if (!string.IsNullOrWhiteSpace(item.OriginalTitle) && !string.Equals(item.OriginalTitle, item.Name, StringComparison.OrdinalIgnoreCase))
        {
            names.Insert(0, item.OriginalTitle);
        }

        var suffixes = (item is MediaBrowser.Controller.Entities.TV.Series ? cfg.SeriesSuffixes : cfg.MovieSuffixes)
            .Split('|', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries);
        var year = item.ProductionYear;
        Candidate? best = null;
        double bestScore = 0;
        var tried = 0;
        foreach (var name in names)
        {
            foreach (var suffix in suffixes)
            {
                if (tried++ >= 4)
                {
                    break;
                }

                var q = $"{name} {(item is MediaBrowser.Controller.Entities.TV.Series ? string.Empty : year?.ToString(System.Globalization.CultureInfo.InvariantCulture))} {suffix}".Replace("  ", " ", StringComparison.Ordinal);
                foreach (var c in await finder.SearchAsync(q, 6, ct).ConfigureAwait(false))
                {
                    var s = ThemeFinder.Score(c, names, year, cfg.MinSeconds, cfg.MaxSeconds);
                    if (s > bestScore)
                    {
                        bestScore = s;
                        best = c;
                    }
                }

                if (bestScore >= 75)
                {
                    return best;
                }
            }
        }

        return bestScore >= 55 ? best : null;
    }

    public static ThemeRecord Rec(BaseItem item, string status, string? url, string? title, string? msg) => new()
    {
        ItemId = item.Id.ToString("N"),
        Name = item.Name,
        Type = item is MediaBrowser.Controller.Entities.TV.Series ? "Dizi" : "Film",
        Year = item.ProductionYear,
        Status = status,
        Url = url,
        VideoTitle = title,
        Message = msg,
        When = DateTime.UtcNow,
    };
}
