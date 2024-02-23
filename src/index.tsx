import React from 'react';
import { createRoot } from "react-dom/client";
import { RouteProvider } from "./router";
import { App } from "./App";


createRoot(document.getElementById("root")!).render(
    <React.StrictMode>
        <RouteProvider>
            <App />
        </RouteProvider>
    </React.StrictMode>,
);
