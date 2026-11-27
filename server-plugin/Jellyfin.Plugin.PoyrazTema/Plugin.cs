using Jellyfin.Plugin.PoyrazTema.Configuration;
using MediaBrowser.Common.Configuration;
using MediaBrowser.Common.Plugins;
using MediaBrowser.Model.Plugins;
using MediaBrowser.Model.Serialization;

namespace Jellyfin.Plugin.PoyrazTema;

/// <summary>Poyraz Tema: tema müziği olmayan film ve dizilere YouTube'dan tema müziği bulur.</summary>
public class Plugin : BasePlugin<PluginConfiguration>, IHasWebPages
{
    public Plugin(IApplicationPaths applicationPaths, IXmlSerializer xmlSerializer)
        : base(applicationPaths, xmlSerializer)
    {
        Instance = this;
    }

    public static Plugin? Instance { get; private set; }

    public override string Name => "Poyraz Tema";

    public override Guid Id => Guid.Parse("5eacc010-65b0-4df5-b3de-6958a110efcb");

    public override string Description => "Tema müziği olmayan film ve dizilere YouTube'dan tema müziği bulur (Themerr'in boş bıraktıkları için).";

    public IEnumerable<PluginPageInfo> GetPages()
    {
        return new[]
        {
            new PluginPageInfo
            {
                Name = Name,
                EmbeddedResourcePath = $"{GetType().Namespace}.Configuration.configPage.html",
            },
        };
    }
}
