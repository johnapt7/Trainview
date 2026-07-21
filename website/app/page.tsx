import { landingMarkup } from "./landing.generated";

export default function Page() {
  return <div dangerouslySetInnerHTML={{ __html: landingMarkup }} />;
}
