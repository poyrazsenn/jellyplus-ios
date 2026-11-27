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
