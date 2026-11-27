using System.Text.Json;

namespace Jellyfin.Plugin.PoyrazTema;

/// <summary>Her yapım için son denemenin sonucu (durum sayfası ve yeniden deneme için).</summary>
public class ThemeRecord
{
    public string ItemId { get; set; } = string.Empty;

    public string Name { get; set; } = string.Empty;

    public string Type { get; set; } = string.Empty;

    public int? Year { get; set; }

    /// <summary>found, notfound, error, manual, existing</summary>
    public string Status { get; set; } = string.Empty;

    public string? Url { get; set; }

    public string? VideoTitle { get; set; }

    public string? Message { get; set; }

    public DateTime When { get; set; }
}

public static class ThemeStore
{
    private static readonly object Gate = new();
    private static readonly JsonSerializerOptions Opts = new() { WriteIndented = true };

    private static string FilePath
    {
        get
        {
            var dir = Plugin.Instance!.DataFolderPath;
            Directory.CreateDirectory(dir);
            return Path.Combine(dir, "themes.json");
        }
    }

    public static Dictionary<string, ThemeRecord> Load()
    {
        lock (Gate)
        {
            try
            {
                if (!File.Exists(FilePath))
                {
                    return new();
                }

                return JsonSerializer.Deserialize<Dictionary<string, ThemeRecord>>(File.ReadAllText(FilePath)) ?? new();
            }
            catch
            {
                return new();
            }
        }
    }

    public static void Save(Dictionary<string, ThemeRecord> d)
    {
        lock (Gate)
        {
            File.WriteAllText(FilePath, JsonSerializer.Serialize(d, Opts));
        }
    }

    public static void Put(ThemeRecord r)
    {
        lock (Gate)
        {
            var d = Load();
            d[r.ItemId] = r;
            Save(d);
        }
    }
}
