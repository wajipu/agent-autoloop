import { createRoot } from "react-dom/client";

import App from "@/App";
import "@/index.css";

// 主题跟随系统，且系统切换时实时变（index.html 里的内联脚本只负责首帧不闪）。
const scheme = matchMedia("(prefers-color-scheme: dark)");
const applyScheme = () => document.documentElement.classList.toggle("dark", scheme.matches);
applyScheme();
scheme.addEventListener("change", applyScheme);

createRoot(document.getElementById("root")!).render(<App />);
