unit TextRenderer;

interface

uses
  TextRendererTypes;

type
  TCustomTextRenderer = class abstract
  public
    function BackendName: string; virtual; abstract;
    function Render(const ARequest: TTextRenderRequest;
      out AMetrics: TTextRenderMetrics): TTextRenderImage; virtual; abstract;
  end;

implementation

end.
