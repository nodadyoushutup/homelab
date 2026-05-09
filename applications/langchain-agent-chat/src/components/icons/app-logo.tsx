import { APP_LOGO_SRC } from "@/lib/branding";

export function AppLogo({
  className,
  alt = "",
  width = 32,
  height = 32,
}: {
  className?: string;
  alt?: string;
  width?: number;
  height?: number;
}) {
  return (
    <img
      src={APP_LOGO_SRC}
      alt={alt}
      width={width}
      height={height}
      className={className}
      style={{ imageRendering: "pixelated" }}
    />
  );
}
