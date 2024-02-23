import { GlTemplate } from "gitlanding/GlTemplate";
import { Header } from "./Header";
import { Footer } from "./Footer";
import { useRoute } from "../router";
import { Home } from "../pages/Home";
import { PageExample } from "../pages/PageExample";
import { FourOhFour } from "../pages/FourOFour";
import { ThemeProvider } from "../theme";

export function App() {
	const route = useRoute();
	return (
		<ThemeProvider>
			<GlTemplate
				header={<Header />}
				headerOptions={{
					"position": "sticky",
					"isRetracted": "smart",
				}}
				footer={<Footer />}
				body={
					(()=>{
						switch(route.name){
							case "home": return <Home />;
							case "pageExample": return <PageExample />;
							default : return <FourOhFour />;
						}
					})()
				}
			/>
		</ThemeProvider>
	);
}