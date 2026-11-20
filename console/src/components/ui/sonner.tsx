import { Toaster as Sonner, type ToasterProps } from "sonner";

// 不用 next-themes：这个项目是 Vite，主题由 index.html 里的 class 决定，直接跟系统。
const Toaster = ({ ...props }: ToasterProps) => {
  return <Sonner theme="system" className="toaster group" position="top-center" {...props} />;
};

export { Toaster };
