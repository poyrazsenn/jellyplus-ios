using MediaBrowser.Controller.Library;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;

namespace Jellyfin.Plugin.PoyrazTema.Api;

/// <summary>Durum sayfası ve elle tema seçimi (yalnızca yönetici).</summary>
[ApiController]
[Route("PoyrazTema")]
[Authorize(Policy = "RequiresElevation")]
public class ThemeController : ControllerBase
{
    private readonly ILibraryManager _library;
    private readonly ThemeFinder _finder;

    public ThemeController(ILibraryManager library, ThemeFinder finder)
    {
        _library = library;
        _finder = finder;
    }

    /// <summary>Son denemeler, en yeni önce.</summary>
    [HttpGet("Status")]
    public ActionResult<IEnumerable<ThemeRecord>> Status()
    {
        return Ok(ThemeStore.Load().Values.OrderByDescending(r => r.When));
    }

    /// <summary>Bir yapım için verilen YouTube bağlantısını theme.mp3 olarak indirir (eskisinin üzerine yazar).</summary>
    [HttpPost("Set")]
    public async Task<ActionResult> Set([FromQuery] string itemId, [FromQuery] string url, CancellationToken ct)
    {
        if (!Guid.TryParse(itemId, out var id) || string.IsNullOrWhiteSpace(url))
        {
            return BadRequest("itemId ve url gerekli.");
        }

        var item = _library.GetItemById(id);
        if (item == null)
        {
            return NotFound();
        }

        var dir = FindThemesTask.FolderFor(item, out var why);
        if (dir == null)
        {
            return BadRequest(why ?? "Klasör bulunamadı.");
        }

        try
        {
            var old = Path.Combine(dir, "theme.mp3");
            if (System.IO.File.Exists(old))
            {
                System.IO.File.Delete(old);
            }

            await _finder.DownloadAsync(url.Trim(), dir, ct).ConfigureAwait(false);
            ThemeStore.Put(FindThemesTask.Rec(item, "manual", url.Trim(), null, null));
            _library.QueueLibraryScan();
            return Ok();
        }
        catch (Exception e)
        {
            ThemeStore.Put(FindThemesTask.Rec(item, "error", url.Trim(), null, e.Message));
            return BadRequest(e.Message);
        }
    }

    /// <summary>Teması olmayan yapımlar (isteğe bağlı ada göre süzülür), en yeni eklenenler önce.</summary>
    [HttpGet("Missing")]
    public ActionResult Missing([FromQuery] string? q)
    {
        var cfg = Plugin.Instance!.Configuration;
        var store = ThemeStore.Load();
        var all = FindThemesTask.Missing(_library, cfg);
        var list = all
            .Where(i => string.IsNullOrWhiteSpace(q)
                || i.Name.Contains(q.Trim(), StringComparison.CurrentCultureIgnoreCase)
                || (i.OriginalTitle ?? string.Empty).Contains(q.Trim(), StringComparison.CurrentCultureIgnoreCase))
            .OrderByDescending(i => i.DateCreated)
            .Take(150)
            .Select(i =>
            {
                store.TryGetValue(i.Id.ToString("N"), out var r);
                var dir = FindThemesTask.FolderFor(i, out var why);
                return new
                {
                    ItemId = i.Id.ToString("N"),
                    i.Name,
                    Year = i.ProductionYear,
                    Type = i is MediaBrowser.Controller.Entities.TV.Series ? "Dizi" : "Film",
                    Status = dir == null ? "skipped" : (r?.Status ?? "waiting"),
                    Message = dir == null ? why : r?.Message,
                    Folder = dir ?? (i is MediaBrowser.Controller.Entities.TV.Series ? i.Path : i.ContainingFolderPath),
                };
            });
        var skipped = all.Count(i => FindThemesTask.FolderFor(i, out _) == null);
        return Ok(new { Total = all.Count - skipped, Skipped = skipped, Items = list });
    }

    /// <summary>Tek bir yapım için hemen ara ve indir (gecelik sınırı beklemeden).</summary>
    [HttpPost("Find")]
    public async Task<ActionResult<ThemeRecord>> Find([FromQuery] string itemId, CancellationToken ct)
    {
        if (!Guid.TryParse(itemId, out var id))
        {
            return BadRequest("itemId gerekli.");
        }

        var item = _library.GetItemById(id);
        if (item == null)
        {
            return NotFound();
        }

        var dir = FindThemesTask.FolderFor(item, out var why);
        if (dir == null)
        {
            return BadRequest(why ?? "Klasör bulunamadı.");
        }

        ThemeRecord rec;
        try
        {
            var best = await FindThemesTask.FindBestAsync(_finder, item, Plugin.Instance!.Configuration, ct).ConfigureAwait(false);
            if (best == null)
            {
                rec = FindThemesTask.Rec(item, "notfound", null, null, "Uygun sonuç bulunamadı. Bağlantıyı elle verebilirsin.");
            }
            else
            {
                await _finder.DownloadAsync(best.Url, dir, ct).ConfigureAwait(false);
                rec = FindThemesTask.Rec(item, "found", best.Url, best.Title, null);
                _library.QueueLibraryScan();
            }
        }
        catch (Exception e)
        {
            rec = FindThemesTask.Rec(item, "error", null, null, e.Message);
        }

        ThemeStore.Put(rec);
        return Ok(rec);
    }

    /// <summary>Kaydı sil: bir sonraki çalıştırmada yeniden aransın.</summary>
    [HttpPost("Retry")]
    public ActionResult Retry([FromQuery] string itemId)
    {
        var d = ThemeStore.Load();
        d.Remove(itemId);
        ThemeStore.Save(d);
        return Ok();
    }
}
