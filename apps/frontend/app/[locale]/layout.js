import {NextIntlClientProvider} from 'next-intl';
import {getMessages} from 'next-intl/server';
import '../globals.css';

export const metadata = {
  title: 'WORKFORCE AI',
  description: 'Motor de Confianza Operativa™ — gestión de fuerza laboral con evidencia biométrica',
};

export default async function LocaleLayout({children, params: {locale}}) {
  const messages = await getMessages();
  return (
    <html lang={locale}>
      <body>
        <NextIntlClientProvider messages={messages}>
          {children}
        </NextIntlClientProvider>
      </body>
    </html>
  );
}
