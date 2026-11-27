using MediaBrowser.Model.Plugins;

namespace Jellyfin.Plugin.PoyrazTema.Configuration;

public class PluginConfiguration : BasePluginConfiguration
{
    /// <summary>Filmlere tema ara.</summary>
    public bool Movies { get; set; } = true;

    /// <summary>Dizilere tema ara.</summary>
    public bool Series { get; set; } = true;

    /// <summary>Bir çalıştırmada en fazla kaç yapım denensin (YouTube'u yormamak için).</summary>
    public int MaxPerRun { get; set; } = 150;

    /// <summary>Kabul edilen en kısa ve en uzun süre (saniye).</summary>
    public int MinSeconds { get; set; } = 30;

    public int MaxSeconds { get; set; } = 360;

    /// <summary>Bulunamayanlar kaç gün sonra yeniden denensin.</summary>
    public int RetryDays { get; set; } = 14;

    /// <summary>Arama sonuna eklenecek ifadeler (sırayla denenir).</summary>
    public string MovieSuffixes { get; set; } = "main theme|theme song|soundtrack main title";

    public string SeriesSuffixes { get; set; } = "opening theme|intro theme|main title theme|jenerik müziği";
}
